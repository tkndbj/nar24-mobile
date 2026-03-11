// lib/screens/food/food_cargo_screen.dart
//
// Changes vs original:
//  • FCM topic subscription on mount (food_couriers)
//  • Foreground message handler → shows themed SnackBar
//  • Notification bell icon in AppBar with unread badge
//  • _NotificationPanel — slides up from bottom, shows
//    food_courier_notifications (isActive == true), real-time
//  • Background / terminated message opens the screen via GoRouter

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import '../../auth_service.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:rxdart/rxdart.dart';

// ─── FCM topic (must match Cloud Function constant) ──────────────────────────
const _kFcmTopic = 'food_couriers';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class FoodCargoScreen extends StatefulWidget {
  const FoodCargoScreen({super.key});

  @override
  State<FoodCargoScreen> createState() => _FoodCargoScreenState();
}

class _FoodCargoScreenState extends State<FoodCargoScreen> {
  final _messaging = FirebaseMessaging.instance;
  bool _notifPanelOpen = false;

  // Real-time unread count from food_courier_notifications
  Stream<int>? _unreadCountStream;

  @override
  void initState() {
    super.initState();
    _setupFcm();
    _setupUnreadStream();
  }

  // ── FCM setup ──────────────────────────────────────────────────────────────

  Future<void> _setupFcm() async {
    // 1. Request permission (iOS / macOS)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Subscribe to the shared courier topic
    await _messaging.subscribeToTopic(_kFcmTopic);
    debugPrint('[FCM] Subscribed to topic: $_kFcmTopic');

    // 3. Foreground messages — show custom in-app banner
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 4. App was in background and user tapped notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 5. App was terminated — check if launched via notification
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    if (!mounted) return;

    final data  = message.data;
    final type  = data['type'] as String? ?? '';
    final title = message.notification?.title ?? '';
    final body  = message.notification?.body  ?? '';

    final isOrderReady = type == 'order_ready';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(isOrderReady ? '📦' : '⏳', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (body.isNotEmpty)
                    Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: isOrderReady ? Colors.green[800] : Colors.orange[800],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
         onPressed: () {
  setState(() => _notifPanelOpen = true);
  _markAllAsRead();
},
        ),
      ),
    );
  }

    Future<void> _markAllAsRead() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  // One write. That's it. No matter how many notifications exist.
  await FirebaseFirestore.instance
      .collection('courier_notification_reads')
      .doc(uid)
      .set({'lastReadAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
}

  void _handleNotificationTap(RemoteMessage message) {
    // App opened from a notification — open the cargo screen (already here)
    // and pop open the notification panel
    if (mounted) {
      setState(() => _notifPanelOpen = true);
    }
  }

  // ── Unread badge ───────────────────────────────────────────────────────────

void _setupUnreadStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  // Stream both sources together
  final notifsStream = FirebaseFirestore.instance
      .collection('food_courier_notifications')
      .where('isActive', isEqualTo: true)
      .snapshots();

  final readStream = FirebaseFirestore.instance
      .collection('courier_notification_reads')
      .doc(uid)
      .snapshots();

  _unreadCountStream = Rx.combineLatest2(
    notifsStream,
    readStream,
    (QuerySnapshot notifs, DocumentSnapshot read) {
      final lastReadAt = (read.data() as Map<String, dynamic>?)?['lastReadAt'] as Timestamp?;
      if (lastReadAt == null) return notifs.size;
      return notifs.docs.where((doc) {
        final createdAt = doc['createdAt'] as Timestamp?;
        if (createdAt == null) return false;
        return createdAt.compareTo(lastReadAt) > 0;
      }).length;
    },
  );
}

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    // Unsubscribe when a courier logs out (handled in _confirmLogout too)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user   = FirebaseAuth.instance.currentUser;
    if (user == null) return const _UnauthView();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loc    = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
            // ── Notification bell with unread badge ──────────────────
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
              onPressed: () async {
                await _confirmLogout(context, loc);
                // Unsubscribe from FCM topic on logout
                await _messaging.unsubscribeFromTopic(_kFcmTopic);
              },
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.orange,
            unselectedLabelColor:
                isDark ? Colors.grey[400] : Colors.grey[500],
            indicatorColor: Colors.orange,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: loc.foodCargoPoolTab),
              Tab(text: loc.foodCargoMyDeliveriesTab),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _PoolTab(currentUser: user, isDark: isDark),
                _MyDeliveriesTab(currentUser: user, isDark: isDark),
              ],
            ),

            // ── Slide-up notification panel ──────────────────────────
            if (_notifPanelOpen)
              _NotificationPanel(
                isDark: isDark,
                onClose: () => setState(() => _notifPanelOpen = false),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PANEL — real-time list of food_courier_notifications
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationPanel extends StatelessWidget {
  final bool isDark;
  final VoidCallback onClose;

  const _NotificationPanel({required this.isDark, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // Prevent tap-through
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF211F31) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
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

                  // Header
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

                  // Notification list
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('food_courier_notifications')
                          .where('isActive', isEqualTo: true)
                          .orderBy('createdAt', descending: true)
                          .limit(30)
                          .snapshots(),
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
                                Text('🔔',
                                    style: const TextStyle(fontSize: 40)),
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
    final type          = data['type'] as String? ?? '';
    final restaurantName = data['restaurantName'] as String? ?? '';
    final itemCount     = (data['itemCount'] as num?)?.toInt() ?? 0;
    final totalPrice    = (data['totalPrice'] as num?)?.toDouble() ?? 0;
    final currency      = data['currency'] as String? ?? 'TL';
    final deliveryCity  = data['deliveryCity'] as String? ?? '';
    final msgTr         = data['message_tr'] as String? ?? '';
    final createdAt     = data['createdAt'] as Timestamp?;

    final isOrderReady = type == 'order_ready';
    final color        = isOrderReady ? Colors.green : Colors.orange;
    final emoji        = isOrderReady ? '📦' : '⏳';
    final label        = isOrderReady ? 'HAZIR' : 'YAKINDA HAZIR';

    final timeStr = createdAt != null
        ? DateFormat('HH:mm').format(createdAt.toDate())
        : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? color.withOpacity(0.08)
            : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label + time
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Restaurant name
                Text(
                  restaurantName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 2),

                // Message
                Text(
                  msgTr,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),

                if (deliveryCity.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13,
                          color: isDark
                              ? Colors.grey[500]
                              : Colors.grey[500]),
                      const SizedBox(width: 3),
                      Text(
                        deliveryCity,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                        ),
                      ),
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
// LOGOUT (unchanged)
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
    await AuthService().logout();
    if (context.mounted) context.go('/');
  } catch (_) {
    if (context.mounted) Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POOL TAB (unchanged from original except stream init pattern kept)
// ─────────────────────────────────────────────────────────────────────────────

class _PoolTab extends StatefulWidget {
  final User currentUser;
  final bool isDark;
  const _PoolTab({required this.currentUser, required this.isDark});

  @override
  State<_PoolTab> createState() => _PoolTabState();
}

class _PoolTabState extends State<_PoolTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('orders-food')
        .where('status', isEqualTo: 'ready')
        .orderBy('updatedAt', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }
        if (snap.hasError) {
          return _ErrorView(message: snap.error.toString());
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return _EmptyState(
            emoji: '📦',
            title: loc.foodCargoPoolEmpty,
            subtitle: loc.foodCargoPoolEmptySub,
            isDark: widget.isDark,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: docs.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _CargoOrderCard(
              orderId: docs[i].id,
              data: docs[i].data(),
              isDark: widget.isDark,
              isPool: true,
              currentUser: widget.currentUser,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY DELIVERIES TAB (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _MyDeliveriesTab extends StatefulWidget {
  final User currentUser;
  final bool isDark;
  const _MyDeliveriesTab({required this.currentUser, required this.isDark});

  @override
  State<_MyDeliveriesTab> createState() => _MyDeliveriesTabState();
}

class _MyDeliveriesTabState extends State<_MyDeliveriesTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection('orders-food')
        .where('cargoUserId', isEqualTo: widget.currentUser.uid)
        .where('status', isEqualTo: 'out_for_delivery')
        .orderBy('assignedAt', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return _EmptyState(
            emoji: '🛵',
            title: loc.foodCargoMyEmpty,
            subtitle: loc.foodCargoMyEmptySub,
            isDark: widget.isDark,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: docs.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _CargoOrderCard(
              orderId: docs[i].id,
              data: docs[i].data(),
              isDark: widget.isDark,
              isPool: false,
              currentUser: widget.currentUser,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER CARD (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _CargoOrderCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool isDark;
  final bool isPool;
  final User currentUser;

  const _CargoOrderCard({
    required this.orderId,
    required this.data,
    required this.isDark,
    required this.isPool,
    required this.currentUser,
  });

  @override
  State<_CargoOrderCard> createState() => _CargoOrderCardState();
}

class _CargoOrderCardState extends State<_CargoOrderCard> {
  bool _loading = false;

  Map<String, dynamic>? get _address =>
      widget.data['deliveryAddress'] as Map<String, dynamic>?;

  List<dynamic> get _items =>
      widget.data['items'] as List<dynamic>? ?? const [];

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

  Future<void> _assignOrder() async {
    final loc = AppLocalizations.of(context);
    final restaurantName = widget.data['restaurantName'] as String? ?? '—';
    final city = _address?['city'] as String? ?? '—';

    final confirmed = await showCupertinoDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CupertinoAlertDialog(
            title: Text(loc.foodCargoTakeConfirmTitle),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(loc.foodCargoTakeConfirmBody(restaurantName, city)),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(loc.foodCargoCancel),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(loc.foodCargoTakeConfirmOk),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) return;

    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;

      await db.runTransaction((tx) async {
        final ref = db.collection('orders-food').doc(widget.orderId);
        final snap = await tx.get(ref);

        if (!snap.exists) throw Exception('not_found');

        final currentStatus = snap.data()?['status'] as String?;
        if (currentStatus != 'ready') throw Exception('already_taken');

        final displayName = widget.currentUser.displayName ??
            widget.currentUser.email ??
            'Cargo';

        tx.update(ref, {
          'cargoUserId': widget.currentUser.uid,
          'cargoName': displayName,
          'status': 'out_for_delivery',
          'assignedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // The Firestore trigger onFoodOrderStatusChange will automatically
        // deactivate the food_courier_notifications doc for this order.
      });
    } catch (e) {
      if (!context.mounted) return;
      final loc = AppLocalizations.of(context);
      final msg = e.toString().contains('already_taken')
          ? loc.foodCargoAlreadyTaken
          : loc.foodCargoAssignError;
      _showSnack(msg, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markDelivered() async {
    final loc = AppLocalizations.of(context);
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateFoodOrderStatus');
      await callable.call({
        'orderId': widget.orderId,
        'newStatus': 'delivered',
      });
      if (mounted) _showSnack(loc.foodCargoDeliveredSuccess);
    } catch (e) {
      if (mounted) {
        _showSnack(AppLocalizations.of(context).foodCargoAssignError,
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      uri =
          Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final loc = AppLocalizations.of(context);

    final restaurantName =
        widget.data['restaurantName'] as String? ?? '—';
    final restaurantImage =
        widget.data['restaurantProfileImage'] as String?;
    final buyerName = widget.data['buyerName'] as String? ?? '—';
    final totalPrice =
        (widget.data['totalPrice'] as num?)?.toDouble() ?? 0;
    final currency = widget.data['currency'] as String? ?? 'TL';
    final isPaid = widget.data['isPaid'] as bool? ?? false;
    final itemCount =
        (widget.data['itemCount'] as num?)?.toInt() ?? _items.length;
    final orderId = widget.orderId.substring(0, 8).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2D2B3F)
              : const Color(0xFFD1D5DB),
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
                    color: isDark
                        ? const Color(0xFF2D2B3F)
                        : Colors.orange[50],
                    child: restaurantImage != null &&
                            restaurantImage.isNotEmpty
                        ? Image.network(
                            restaurantImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Text('🍽️',
                                  style: TextStyle(fontSize: 22)),
                            ),
                          )
                        : const Center(
                            child: Text('🍽️',
                                style: TextStyle(fontSize: 22)),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurantName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${loc.foodCargoOrderId} #$orderId',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey[500]
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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
                      color: isDark
                          ? Colors.orange[300]
                          : Colors.orange[700],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark
                ? const Color(0xFF2D2B3F)
                : const Color(0xFFE5E7EB),
          ),

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
                  value: _itemsSummary(loc, itemCount),
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.location_on_rounded,
                  label: loc.foodCargoAddressLabel,
                  value: _addressLine,
                  isDark: isDark,
                  valueColor:
                      isDark ? Colors.blue[300] : Colors.blue[700],
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.receipt_rounded,
                  label: loc.foodCargoTotalLabel,
                  value:
                      '${totalPrice.toStringAsFixed(0)} $currency  ·  ${isPaid ? loc.foodCargoPaid : loc.foodCargoPaymentAtDoor}',
                  isDark: isDark,
                  valueColor: isPaid
                      ? (isDark ? Colors.green[400] : Colors.green[700])
                      : (isDark
                          ? Colors.orange[300]
                          : Colors.orange[700]),
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: isDark
                ? const Color(0xFF2D2B3F)
                : const Color(0xFFE5E7EB),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: widget.isPool
                ? _PoolActions(
                    loading: _loading,
                    onAssign: _assignOrder,
                    loc: loc,
                  )
                : _MyDeliveryActions(
                    loading: _loading,
                    isDark: isDark,
                    hasPhone: _customerPhone.isNotEmpty,
                    onCall: _callPhone,
                    onMap: _openMap,
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
// ACTION WIDGETS (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _PoolActions extends StatelessWidget {
  final bool loading;
  final VoidCallback onAssign;
  final AppLocalizations loc;

  const _PoolActions(
      {required this.loading,
      required this.onAssign,
      required this.loc});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onAssign,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.orange.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delivery_dining_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    loc.foodCargoTakeOrder,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MyDeliveryActions extends StatelessWidget {
  final bool loading;
  final bool isDark;
  final bool hasPhone;
  final VoidCallback onCall;
  final VoidCallback onMap;
  final VoidCallback onDelivered;
  final AppLocalizations loc;

  const _MyDeliveryActions({
    required this.loading,
    required this.isDark,
    required this.hasPhone,
    required this.onCall,
    required this.onMap,
    required this.onDelivered,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
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
            onPressed: loading ? null : onDelivered,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.green.withOpacity(0.5),
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
                : Text(
                    loc.foodCargoMarkDelivered,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS (unchanged)
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
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: enabled
              ? color.withOpacity(isDark ? 0.13 : 0.08)
              : (isDark
                  ? const Color(0xFF2D2B3F)
                  : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withOpacity(0.25)
                : (isDark
                    ? const Color(0xFF2D2B3F)
                    : const Color(0xFFD1D5DB)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled
                  ? color
                  : (isDark ? Colors.grey[600] : Colors.grey[400]),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? color
                    : (isDark ? Colors.grey[600] : Colors.grey[400]),
              ),
            ),
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
          child: Icon(
            icon,
            size: 15,
            color: isDark ? Colors.grey[500] : Colors.grey[400],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 78,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ??
                  (isDark ? Colors.grey[200] : Colors.grey[800]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE BADGE (unchanged)
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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
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
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green
              .withOpacity(widget.isDark ? 0.15 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.isDark
                    ? Colors.green[400]
                    : Colors.green[700],
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLACEHOLDERS (unchanged)
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
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
        child: CircularProgressIndicator(
            color: Colors.orange, strokeWidth: 2.5),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
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
            const Icon(Icons.lock_rounded,
                size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              loc.foodCargoSignInRequired,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}