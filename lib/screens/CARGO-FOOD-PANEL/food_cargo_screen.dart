// lib/screens/CARGO-FOOD-PANEL/food_cargo_screen.dart
//
// Single-view courier screen. Orders are auto-assigned to the courier by the
// backend (CF-54); the courier never self-assigns. This screen only shows the
// courier's own in-flight deliveries (status ∈ {assigned, out_for_delivery})
// and lets them mark pickup / delivery.
//
// Push notifications about newly assigned orders arrive per-device via the
// CF-46 FCM fan-out that watches users/{uid}/notifications. No topic
// subscription is required.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth_service.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/courier_location_service.dart';
import './courier_route_screen.dart';

// Legacy pool-era topic. We unsubscribe on init so lingering subscriptions
// on existing devices go away — targeted per-device pushes replace it.
const _kLegacyPoolTopic = 'food_couriers';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class FoodCargoScreen extends StatefulWidget {
  const FoodCargoScreen({super.key});

  @override
  State<FoodCargoScreen> createState() => _FoodCargoScreenState();
}

class _FoodCargoScreenState extends State<FoodCargoScreen>
    with WidgetsBindingObserver {
  final _messaging = FirebaseMessaging.instance;
  bool _notifPanelOpen = false;
  final _localReadController = BehaviorSubject<DateTime?>.seeded(null);
  Stream<int>? _unreadCountStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _courierNotifsStream;
  bool _isOnline = true;
  StreamSubscription<bool>? _connSub;
  String? _highlightedOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Per-courier notification feed (written by CF-40 / CF-46 via
    // users/{uid}/notifications → this legacy collection is kept for the
    // in-app bell list so the UI shows platform-wide heads-up messages).
    _courierNotifsStream = FirebaseFirestore.instance
        .collection('food_courier_notifications')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .shareReplay(maxSize: 1);
    _setupFcm();
    _setupUnreadStream();
    CourierLocationService.instance.startTracking();
    _connSub =
        CourierLocationService.instance.connectionStream.listen((connected) {
      if (mounted && _isOnline != connected) {
        setState(() => _isOnline = connected);
      }
    });
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> _setupFcm() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    // Clean up the obsolete pool-era topic subscription. Safe to call even if
    // the device was never subscribed.
    try {
      await _messaging.unsubscribeFromTopic(_kLegacyPoolTopic);
    } catch (_) {}
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    final type = data['type'] as String? ?? '';
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final isAssigned = type == 'order_assigned';

    final bgColor = isAssigned ? Colors.purple[800] : Colors.orange[800];
    final emoji = isAssigned ? '🎯' : '🔔';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  if (body.isNotEmpty)
                    Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            if (isAssigned) {
              final orderId = data['orderId'] as String?;
              if (orderId != null && orderId.isNotEmpty) {
                setState(() => _highlightedOrderId = orderId);
              }
            } else {
              setState(() => _notifPanelOpen = true);
              _markAllAsRead();
            }
          },
        ),
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    _localReadController.add(DateTime.now());
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('courier_notification_reads')
        .doc(uid)
        .set({'lastReadAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    final type = data['type'] as String? ?? '';

    if (type == 'order_assigned') {
      final orderId = data['orderId'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        setState(() => _highlightedOrderId = orderId);
      }
    } else {
      setState(() => _notifPanelOpen = true);
    }
  }

  // ── Unread stream ─────────────────────────────────────────────────────────

  void _setupUnreadStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final readStream = FirebaseFirestore.instance
        .collection('courier_notification_reads')
        .doc(uid)
        .snapshots();

    _unreadCountStream = Rx.combineLatest3(
      _courierNotifsStream,
      readStream,
      _localReadController.stream,
      (QuerySnapshot notifs, DocumentSnapshot read, DateTime? localReadAt) {
        final firestoreTs =
            (read.data() as Map<String, dynamic>?)?['lastReadAt'] as Timestamp?;
        DateTime? effectiveReadAt = firestoreTs?.toDate();
        if (localReadAt != null) {
          if (effectiveReadAt == null || localReadAt.isAfter(effectiveReadAt)) {
            effectiveReadAt = localReadAt;
          }
        }
        if (effectiveReadAt == null) return notifs.size;
        return notifs.docs.where((doc) {
          final createdAt = doc['createdAt'] as Timestamp?;
          if (createdAt == null) return false;
          return createdAt.toDate().isAfter(effectiveReadAt!);
        }).length;
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      CourierLocationService.instance.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      CourierLocationService.instance.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    CourierLocationService.instance.stopTracking();
    _localReadController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const _UnauthView();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Text(loc.foodCargoTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            _LiveBadge(isDark: isDark),
          ],
        ),
        actions: [
          StreamBuilder<int>(
            stream: _unreadCountStream,
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_rounded),
                    tooltip: 'Notifications',
                    onPressed: () {
                      final opening = !_notifPanelOpen;
                      setState(() => _notifPanelOpen = opening);
                      if (opening) _markAllAsRead();
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: loc.pastFoodCargosTitle,
            onPressed: () => context.push('/past-food-cargos'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: loc.foodCargoLogout,
            onPressed: () => _confirmLogout(context, loc),
          ),
        ],
      ),
      body: Stack(
        children: [
          _DeliveriesList(
            currentUser: user,
            isDark: isDark,
            highlightedOrderId: _highlightedOrderId,
          ),
          if (!_isOnline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 2,
                color: Colors.red[700],
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Çevrimdışı — işlemler bağlantı kurulunca gönderilecek',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_notifPanelOpen)
            _NotificationPanel(
              isDark: isDark,
              onClose: () => setState(() => _notifPanelOpen = false),
              notifsStream: _courierNotifsStream,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PANEL
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationPanel extends StatelessWidget {
  final bool isDark;
  final VoidCallback onClose;
  final Stream<QuerySnapshot<Map<String, dynamic>>> notifsStream;
  const _NotificationPanel({
    required this.isDark,
    required this.onClose,
    required this.notifsStream,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF211F31) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600]),
                          onPressed: onClose,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: notifsStream,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.orange, strokeWidth: 2));
                        }
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔔',
                                    style: TextStyle(fontSize: 40)),
                                const SizedBox(height: 12),
                                Text(
                                  'No active notifications',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final data = docs[i].data();
                            return _NotifCard(
                                data: data, isDark: isDark, onClose: onClose);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isDark;
  final VoidCallback onClose;
  const _NotifCard(
      {required this.data, required this.isDark, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final restaurantName = data['restaurantName'] as String? ?? '';
    final deliveryCity = data['deliveryCity'] as String? ?? '';
    final msgTr = data['message_tr'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final color = type == 'heads_up' ? Colors.orange : Colors.blue;
    final emoji = type == 'heads_up' ? '⏳' : '🔔';
    final label = type == 'heads_up' ? 'YAKINDA HAZIR' : 'BİLDİRİM';
    final timeStr =
        createdAt != null ? DateFormat('HH:mm').format(createdAt.toDate()) : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.08) : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ),
                    const Spacer(),
                    Text(timeStr,
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 6),
                Text(restaurantName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.grey[900])),
                const SizedBox(height: 2),
                Text(msgTr,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600])),
                if (deliveryCity.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13,
                          color: isDark ? Colors.grey[500] : Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(deliveryCity,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[500])),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _confirmLogout(BuildContext context, AppLocalizations loc) async {
  final confirmed = await showCupertinoDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CupertinoAlertDialog(
          title: Text(loc.foodCargoLogout),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(loc.foodCargoLogoutConfirm),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(loc.foodCargoCancel),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(loc.foodCargoLogout),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await CourierLocationService.instance.stopTracking();
    await AuthService().logout();
    if (context.mounted) context.go('/');
  } catch (_) {
    if (context.mounted) Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERY ORDER DOC WRAPPER (couples a Firestore doc with its collection)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderDoc {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String collection; // 'orders-food' | 'orders-market'
  _OrderDoc(this.doc, this.collection);
}

// ─────────────────────────────────────────────────────────────────────────────
// DELIVERIES LIST — courier's in-flight orders (assigned + out_for_delivery)
// ─────────────────────────────────────────────────────────────────────────────

class _DeliveriesList extends StatefulWidget {
  final User currentUser;
  final bool isDark;
  final String? highlightedOrderId;

  const _DeliveriesList({
    required this.currentUser,
    required this.isDark,
    this.highlightedOrderId,
  });

  @override
  State<_DeliveriesList> createState() => _DeliveriesListState();
}

class _DeliveriesListState extends State<_DeliveriesList>
    with AutomaticKeepAliveClientMixin {
  late Stream<List<_OrderDoc>> _stream;
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  final Set<String> _removedLocally = {};
  final Map<String, StreamSubscription> _actionListeners = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stream = _buildStream(widget.currentUser.uid);
  }

  @override
  void didUpdateWidget(_DeliveriesList old) {
    super.didUpdateWidget(old);
    if (old.currentUser.uid != widget.currentUser.uid) {
      _stream = _buildStream(widget.currentUser.uid);
    }
  }

  Stream<List<_OrderDoc>> _buildStream(String uid) {
    const inFlight = ['assigned', 'out_for_delivery'];

    final foodStream = FirebaseFirestore.instance
        .collection('orders-food')
        .where('cargoUserId', isEqualTo: uid)
        .where('status', whereIn: inFlight)
        .snapshots();

    final marketStream = FirebaseFirestore.instance
        .collection('orders-market')
        .where('cargoUserId', isEqualTo: uid)
        .where('status', whereIn: inFlight)
        .snapshots();

    return Rx.combineLatest2<
        QuerySnapshot<Map<String, dynamic>>,
        QuerySnapshot<Map<String, dynamic>>,
        List<_OrderDoc>>(foodStream, marketStream, (food, market) {
      final all = <_OrderDoc>[
        ...food.docs.map((d) => _OrderDoc(d, 'orders-food')),
        ...market.docs.map((d) => _OrderDoc(d, 'orders-market')),
      ];
      all.sort((a, b) {
        final aTs = a.doc.data()['assignedAt'] as Timestamp?;
        final bTs = b.doc.data()['assignedAt'] as Timestamp?;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return aTs.compareTo(bTs);
      });
      return all;
    });
  }

  void _listenForActionResult(String actionId, String orderId) {
    final sub = FirebaseFirestore.instance
        .collection('courier_actions')
        .doc(actionId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final status = snap.data()?['status'] as String?;

      if (status == 'completed') {
        _actionListeners[actionId]?.cancel();
        _actionListeners.remove(actionId);
      } else if (status == 'failed') {
        _actionListeners[actionId]?.cancel();
        _actionListeners.remove(actionId);

        setState(() => _removedLocally.remove(orderId));

        final error = snap.data()?['error'] as String? ?? 'Bilinmeyen hata';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Teslimat başarısız: $error'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
      }
    });
    _actionListeners[actionId] = sub;
  }

  @override
  void dispose() {
    for (final sub in _actionListeners.values) {
      sub.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = AppLocalizations.of(context);

    return StreamBuilder<List<_OrderDoc>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }

        if (snap.hasError) {
          return _ErrorView(message: 'Teslimatlar yüklenemedi: ${snap.error}');
        }

        final docs = [...(snap.data ?? const <_OrderDoc>[])]
          ..removeWhere((p) => _removedLocally.contains(p.doc.id));

        if (docs.isEmpty) {
          return _EmptyState(
            emoji: '🛵',
            title: loc.foodCargoMyEmpty,
            subtitle: loc.foodCargoMyEmptySub,
            isDark: widget.isDark,
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CourierRouteScreen()),
                  ),
                  icon: const Icon(Icons.route_rounded, size: 18),
                  label: Text(
                    '${docs.length} Teslimat · Rotamı Gör',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final order = docs[i];
                    final docId = order.doc.id;
                    final collection = order.collection;
                    _cardKeys[docId] ??= GlobalKey();
                    final isHit = docId == widget.highlightedOrderId;

                    if (isHit) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final ctx = _cardKeys[docId]?.currentContext;
                        if (ctx != null) {
                          Scrollable.ensureVisible(ctx,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                              alignment: 0.15);
                        }
                      });
                    }

                    return Padding(
                      key: _cardKeys[docId],
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _CargoOrderCard(
                        orderId: docId,
                        data: order.doc.data(),
                        collection: collection,
                        isDark: widget.isDark,
                        currentUser: widget.currentUser,
                        isHighlighted: isHit,
                        onDeliveredLocally: (actionId) {
                          setState(() => _removedLocally.add(docId));
                          if (actionId.isNotEmpty) {
                            _listenForActionResult(actionId, docId);
                          }
                        },
                      ),
                    );
                  }),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER CARD — single layout, auto-assigned only (no self-assign button)
// ─────────────────────────────────────────────────────────────────────────────

class _CargoOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final String collection;
  final bool isDark;
  final User currentUser;
  final bool isHighlighted;
  final void Function(String actionDocId)? onDeliveredLocally;

  const _CargoOrderCard({
    required this.orderId,
    required this.data,
    required this.collection,
    required this.isDark,
    required this.currentUser,
    this.isHighlighted = false,
    this.onDeliveredLocally,
  });

  bool get isMarket => collection == 'orders-market';

  @override
  State<_CargoOrderCard> createState() => _CargoOrderCardState();
}

class _CargoOrderCardState extends State<_CargoOrderCard> {
  bool _loading = false;

  Map<String, dynamic>? get _address =>
      widget.data['deliveryAddress'] as Map<String, dynamic>?;

  List<dynamic> get _items =>
      widget.data['items'] as List<dynamic>? ?? const [];

  String? _firstItemImage() {
    if (_items.isEmpty) return null;
    final first = _items.first;
    if (first is! Map<String, dynamic>) return null;
    final url = first['imageUrl'] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  String get _customerPhone {
    final addr = _address;
    final addrPhone = (addr?['phoneNumber'] as String? ?? '').trim();
    if (addrPhone.isNotEmpty) return addrPhone;
    return (widget.data['buyerPhone'] as String? ?? '').trim();
  }

  String get _addressLine {
    final addr = _address;
    if (addr == null) return '—';
    return [
      addr['addressLine1'] as String? ?? '',
      addr['addressLine2'] as String? ?? '',
      addr['city'] as String? ?? '',
    ].where((s) => s.isNotEmpty).join(', ');
  }

  GeoPoint? get _geoPoint {
    final loc = _address?['location'];
    return loc is GeoPoint ? loc : null;
  }

  String _timeAgo(AppLocalizations loc) {
    final ts = widget.data['updatedAt'];
    if (ts == null) return '';
    final dt = (ts as Timestamp).toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return loc.foodCargoJustNow;
    if (diff.inHours < 1) return loc.foodCargoMinAgo(diff.inMinutes);
    return loc.foodCargoHrAgo(diff.inHours, diff.inMinutes % 60);
  }

  String _itemsSummary(AppLocalizations loc, int count) {
    if (_items.isEmpty) return loc.foodCargoItemCount(count);
    final parts = _items.take(2).map((raw) {
      final item = raw as Map<String, dynamic>;
      final name = item['name'] as String? ?? '';
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      return qty > 1 ? '$name ×$qty' : name;
    }).join(', ');
    final overflow = _items.length > 2 ? ' +${_items.length - 2}' : '';
    return '$parts$overflow';
  }

  Future<void> _markPickedUp() async {
    final loc = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final uid = widget.currentUser.uid;
      final displayName = widget.currentUser.displayName ??
          widget.currentUser.email ??
          'Courier';

      final actionRef =
          FirebaseFirestore.instance.collection('courier_actions').doc();
      await actionRef.set({
        'type': 'pickup',
        'collection': widget.collection,
        'orderId': widget.orderId,
        'courierId': uid,
        'courierName': displayName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) _showSnack(loc.foodCargoPickedUpSuccess);
    } catch (_) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context).foodCargoAssignError,
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markDelivered() async {
    final loc = AppLocalizations.of(context);

    final paymentMethod = await _showPaymentSheet();
    if (paymentMethod == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final displayName =
          FirebaseAuth.instance.currentUser!.displayName ?? 'Courier';

      final actionRef =
          FirebaseFirestore.instance.collection('courier_actions').doc();
      await actionRef.set({
        'type': 'deliver',
        'collection': widget.collection,
        'orderId': widget.orderId,
        'courierId': uid,
        'courierName': displayName,
        'paymentMethod': paymentMethod,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      CourierLocationService.instance.updateCurrentOrder(null);
      widget.onDeliveredLocally?.call(actionRef.id);
      if (mounted) _showSnack(loc.foodCargoDeliveredSuccess);
    } catch (_) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context).foodCargoAssignError,
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showPaymentSheet() {
    final isDark = widget.isDark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, 32 + MediaQuery.of(context).padding.bottom),
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
                width: 40,
                height: 4,
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
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ödeme yöntemini seçin',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _PaymentOptionBtn(
                  emoji: '💳',
                  label: 'Kart',
                  color: Colors.blue,
                  isDark: isDark,
                  onTap: () => Navigator.of(context).pop('card'),
                ),
                const SizedBox(width: 12),
                _PaymentOptionBtn(
                  emoji: '💵',
                  label: 'Nakit',
                  color: Colors.green,
                  isDark: isDark,
                  onTap: () => Navigator.of(context).pop('cash'),
                ),
                const SizedBox(width: 12),
                _PaymentOptionBtn(
                  emoji: '🏦',
                  label: 'IBAN',
                  color: Colors.purple,
                  isDark: isDark,
                  onTap: () => Navigator.of(context).pop('iban'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPhone() async {
    final phone = _customerPhone;
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMap() async {
    final geo = _geoPoint;
    Uri uri;
    if (geo != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${geo.latitude},${geo.longitude}');
    } else {
      final q = Uri.encodeComponent(_addressLine);
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final loc = AppLocalizations.of(context);

    final isMarket = widget.isMarket;
    final restaurantName = isMarket
        ? 'Market Sipariş'
        : (widget.data['restaurantName'] as String? ?? '—');
    final restaurantImage = isMarket
        ? _firstItemImage()
        : widget.data['restaurantProfileImage'] as String?;
    final buyerName = widget.data['buyerName'] as String? ?? '—';
    final totalPrice = (widget.data['totalPrice'] as num?)?.toDouble() ?? 0;
    final currency = widget.data['currency'] as String? ?? 'TL';
    final isPaid = widget.data['isPaid'] as bool? ?? false;
    final itemCount =
        (widget.data['itemCount'] as num?)?.toInt() ?? _items.length;
    final orderId = widget.orderId.substring(0, 8).toUpperCase();
    final isScanned = widget.data['sourceType'] == 'scanned_receipt';
    final showMarketBadge = isMarket;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isHighlighted
              ? Colors.orange
              : (isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB)),
          width: widget.isHighlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: isDark ? const Color(0xFF2D2B3F) : Colors.orange[50],
                    child: restaurantImage != null && restaurantImage.isNotEmpty
                        ? Image.network(restaurantImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Text('🍽️',
                                    style: TextStyle(fontSize: 22))))
                        : const Center(
                            child: Text('🍽️', style: TextStyle(fontSize: 22))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(restaurantName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (isScanned)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('FİŞ',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple)),
                            ),
                          if (showMarketBadge)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('MARKET',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${loc.foodCargoOrderId} #$orderId',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withOpacity(0.13)
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _timeAgo(loc),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.orange[300] : Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color:
                  isDark ? const Color(0xFF2D2B3F) : const Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.person_rounded,
                  label: loc.foodCargoCustomer,
                  value: buyerName,
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.fastfood_rounded,
                  label: loc.foodCargoItems,
                  value: isScanned
                      ? 'Harici sipariş (fiş)'
                      : _itemsSummary(loc, itemCount),
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.location_on_rounded,
                  label: loc.foodCargoAddressLabel,
                  value: _addressLine,
                  isDark: isDark,
                  valueColor: isDark ? Colors.blue[300] : Colors.blue[700],
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.receipt_rounded,
                  label: loc.foodCargoTotalLabel,
                  value: totalPrice > 0
                      ? '${totalPrice.toStringAsFixed(0)} $currency  ·  ${isPaid ? loc.foodCargoPaid : loc.foodCargoPaymentAtDoor}'
                      : isScanned
                          ? 'Bilinmiyor (fiş)'
                          : '—',
                  isDark: isDark,
                  valueColor: isPaid
                      ? (isDark ? Colors.green[400] : Colors.green[700])
                      : (isDark ? Colors.orange[300] : Colors.orange[700]),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color:
                  isDark ? const Color(0xFF2D2B3F) : const Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: _MyDeliveryActions(
              loading: _loading,
              isDark: isDark,
              hasPhone: _customerPhone.isNotEmpty,
              orderStatus:
                  (widget.data['status'] as String?) ?? 'assigned',
              onCall: _callPhone,
              onMap: _openMap,
              onPickedUp: _markPickedUp,
              onDelivered: _markDelivered,
              loc: loc,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _MyDeliveryActions extends StatelessWidget {
  final bool loading;
  final bool isDark;
  final bool hasPhone;
  final String orderStatus;
  final VoidCallback onCall;
  final VoidCallback onMap;
  final VoidCallback onPickedUp;
  final VoidCallback onDelivered;
  final AppLocalizations loc;

  const _MyDeliveryActions({
    required this.loading,
    required this.isDark,
    required this.hasPhone,
    required this.orderStatus,
    required this.onCall,
    required this.onMap,
    required this.onPickedUp,
    required this.onDelivered,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    // assigned           → "Teslim Aldım"  (orange, calls onPickedUp)
    // out_for_delivery   → "Teslim Edildi" (green, calls onDelivered)
    final isPickedUp = orderStatus == 'out_for_delivery';
    final label =
        isPickedUp ? loc.foodCargoMarkDelivered : loc.foodCargoMarkPickedUp;
    final onTap = isPickedUp ? onDelivered : onPickedUp;
    final btnColor = isPickedUp ? Colors.green : Colors.orange;

    return Row(
      children: [
        _IconActionBtn(
          icon: Icons.phone_rounded,
          label: loc.foodCargoCallCustomer,
          color: Colors.green,
          isDark: isDark,
          enabled: hasPhone,
          onTap: hasPhone ? onCall : null,
        ),
        const SizedBox(width: 8),
        _IconActionBtn(
          icon: Icons.map_rounded,
          label: loc.foodCargoOpenMap,
          color: Colors.blue,
          isDark: isDark,
          enabled: true,
          onTap: onMap,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: loading ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: btnColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: btnColor.withOpacity(0.5),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _IconActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final bool enabled;
  final VoidCallback? onTap;

  const _IconActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: enabled
              ? color.withOpacity(isDark ? 0.13 : 0.08)
              : (isDark ? const Color(0xFF2D2B3F) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withOpacity(0.25)
                : (isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 20,
                color: enabled
                    ? color
                    : (isDark ? Colors.grey[600] : Colors.grey[400])),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? color
                        : (isDark ? Colors.grey[600] : Colors.grey[400]))),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon,
              size: 15, color: isDark ? Colors.grey[500] : Colors.grey[400]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 78,
          child: Text('$label:',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[500])),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor ??
                      (isDark ? Colors.grey[200] : Colors.grey[800]))),
        ),
      ],
    );
  }
}

class _PaymentOptionBtn extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _PaymentOptionBtn({
    required this.emoji,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  final bool isDark;
  const _LiveBadge({required this.isDark});
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(widget.isDark ? 0.15 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Colors.green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('LIVE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        widget.isDark ? Colors.green[400] : Colors.green[700],
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLACEHOLDERS
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool isDark;

  const _EmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[500] : Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Center(
        child:
            CircularProgressIndicator(color: Colors.orange, strokeWidth: 2.5),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
}

class _UnauthView extends StatelessWidget {
  const _UnauthView();
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(loc.foodCargoSignInRequired,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
