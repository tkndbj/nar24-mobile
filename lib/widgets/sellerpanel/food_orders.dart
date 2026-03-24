import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../utils/food_localization.dart';

const _kPageSize = 15;
const _kInformCooldownMs = 5 * 60 * 1000; // mirrors Cloud Function

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _OrderStatus {
  pending,
  accepted,
  rejected,
  preparing, // kept for parsing/display only — not in any tab filter
  ready,
  out_for_delivery, // ← ADDED (matches Next.js)
  delivered,
  cancelled,
}

enum _TabStatus { pending, accepted, delivered, rejected }

// FIX 1: accepted tab now matches Next.js — [accepted, ready, out_for_delivery]
// (was [accepted, preparing, ready])
const _kTabStatuses = <_TabStatus, List<_OrderStatus>>{
  _TabStatus.pending: [_OrderStatus.pending],
  _TabStatus.accepted: [
    _OrderStatus.accepted,
    _OrderStatus.ready,
    _OrderStatus.out_for_delivery,
  ],
  _TabStatus.delivered: [_OrderStatus.delivered],
  _TabStatus.rejected: [_OrderStatus.rejected, _OrderStatus.cancelled],
};

// FIX 2: removed ready → delivered shortcut — Next.js has no such transition.
// Ready orders show "Waiting for cargo" text only.
const _kNextStatus = <_OrderStatus, _OrderStatus>{};

// ─── Status display config ────────────────────────────────────────────────────

class _StatusCfg {
  final Color bg;
  final Color fg;
  final Color dot;
  final IconData icon;
  const _StatusCfg({
    required this.bg,
    required this.fg,
    required this.dot,
    required this.icon,
  });
}

const _kStatusCfg = <_OrderStatus, _StatusCfg>{
  _OrderStatus.pending: _StatusCfg(
    bg: Color(0xFFFFFBEB),
    fg: Color(0xFFB45309),
    dot: Color(0xFFFBBF24),
    icon: Icons.schedule_rounded,
  ),
  _OrderStatus.accepted: _StatusCfg(
    bg: Color(0xFFF0FDFA),
    fg: Color(0xFF0F766E),
    dot: Color(0xFF2DD4BF),
    icon: Icons.check_circle_outline_rounded,
  ),
  _OrderStatus.preparing: _StatusCfg(
    bg: Color(0xFFEFF6FF),
    fg: Color(0xFF1D4ED8),
    dot: Color(0xFF60A5FA),
    icon: Icons.soup_kitchen_outlined,
  ),
  _OrderStatus.ready: _StatusCfg(
    bg: Color(0xFFF0FDF4),
    fg: Color(0xFF15803D),
    dot: Color(0xFF34D399),
    icon: Icons.inventory_2_outlined,
  ),
  // FIX 3: added out_for_delivery config (mirrors Next.js Bike/gray styling)
  _OrderStatus.out_for_delivery: _StatusCfg(
    bg: Color(0xFFF9FAFB),
    fg: Color(0xFF6B7280),
    dot: Color(0xFF9CA3AF),
    icon: Icons.directions_bike_rounded,
  ),
  _OrderStatus.delivered: _StatusCfg(
    bg: Color(0xFFF9FAFB),
    fg: Color(0xFF6B7280),
    dot: Color(0xFF9CA3AF),
    icon: Icons.check_circle_outline_rounded,
  ),
  _OrderStatus.rejected: _StatusCfg(
    bg: Color(0xFFFFF1F2),
    fg: Color(0xFFDC2626),
    dot: Color(0xFFF87171),
    icon: Icons.cancel_outlined,
  ),
  _OrderStatus.cancelled: _StatusCfg(
    bg: Color(0xFFFFF1F2),
    fg: Color(0xFFDC2626),
    dot: Color(0xFFF87171),
    icon: Icons.cancel_outlined,
  ),
};

// ─── Parsers ──────────────────────────────────────────────────────────────────

_OrderStatus _parseStatus(String? raw) {
  switch (raw) {
    case 'accepted':
      return _OrderStatus.accepted;
    case 'rejected':
      return _OrderStatus.rejected;
    case 'preparing':
      return _OrderStatus.preparing;
    case 'ready':
      return _OrderStatus.ready;
    case 'out_for_delivery': // ← ADDED
      return _OrderStatus.out_for_delivery;
    case 'delivered':
      return _OrderStatus.delivered;
    case 'cancelled':
      return _OrderStatus.cancelled;
    default:
      return _OrderStatus.pending;
  }
}

String _statusToString(_OrderStatus s) {
  switch (s) {
    case _OrderStatus.accepted:
      return 'accepted';
    case _OrderStatus.rejected:
      return 'rejected';
    case _OrderStatus.preparing:
      return 'preparing';
    case _OrderStatus.ready:
      return 'ready';
    case _OrderStatus.out_for_delivery: // ← ADDED
      return 'out_for_delivery';
    case _OrderStatus.delivered:
      return 'delivered';
    case _OrderStatus.cancelled:
      return 'cancelled';
    case _OrderStatus.pending:
      return 'pending';
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _OrderExtra {
  final String name;
  final double price;
  final int quantity;
  const _OrderExtra(
      {required this.name, required this.price, required this.quantity});
}

class _OrderItem {
  final String name;
  final int quantity;
  final double itemTotal;
  final List<_OrderExtra> extras;
  final String specialNotes;
  const _OrderItem({
    required this.name,
    required this.quantity,
    required this.itemTotal,
    required this.extras,
    required this.specialNotes,
  });
}

class _DeliveryAddress {
  final String addressLine1;
  final String addressLine2;
  final String city;
  const _DeliveryAddress({
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
  });
  String get formatted =>
      [addressLine1, addressLine2, city].where((s) => s.isNotEmpty).join(', ');
}

class _FoodOrder {
  final String id;
  final String buyerName;
  final String buyerPhone;
  final List<_OrderItem> items;
  final int itemCount;
  final double subtotal;
  final double deliveryFee;
  final double totalPrice;
  final String currency;
  final _OrderStatus status;
  final String deliveryType;
  final _DeliveryAddress? deliveryAddress;
  final String paymentMethod;
  final bool isPaid;
  final String orderNotes;
  final int estimatedPrepTime;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final Timestamp? lastInformedAt;

  const _FoodOrder({
    required this.id,
    required this.buyerName,
    required this.buyerPhone,
    required this.items,
    required this.itemCount,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalPrice,
    required this.currency,
    required this.status,
    required this.deliveryType,
    required this.deliveryAddress,
    required this.paymentMethod,
    required this.isPaid,
    required this.orderNotes,
    required this.estimatedPrepTime,
    this.createdAt,
    this.updatedAt,
    this.lastInformedAt,
  });

  factory _FoodOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'] as List? ?? [];
    final items = rawItems.map((raw) {
      final item = raw as Map<String, dynamic>;
      final rawExtras = item['extras'] as List? ?? [];
      return _OrderItem(
        name: item['name'] as String? ?? '',
        quantity: (item['quantity'] as num?)?.toInt() ?? 1,
        itemTotal: (item['itemTotal'] as num?)?.toDouble() ?? 0,
        specialNotes: item['specialNotes'] as String? ?? '',
        extras: rawExtras.map((e) {
          final ex = e as Map<String, dynamic>;
          return _OrderExtra(
            name: ex['name'] as String? ?? '',
            price: (ex['price'] as num?)?.toDouble() ?? 0,
            quantity: (ex['quantity'] as num?)?.toInt() ?? 1,
          );
        }).toList(),
      );
    }).toList();

    _DeliveryAddress? deliveryAddress;
    final rawAddr = d['deliveryAddress'] as Map<String, dynamic>?;
    if (rawAddr != null) {
      deliveryAddress = _DeliveryAddress(
        addressLine1: rawAddr['addressLine1'] as String? ?? '',
        addressLine2: rawAddr['addressLine2'] as String? ?? '',
        city: rawAddr['city'] as String? ?? '',
      );
    }

    return _FoodOrder(
      id: doc.id,
      buyerName: d['buyerName'] as String? ?? '',
      buyerPhone: d['buyerPhone'] as String? ?? '',
      items: items,
      itemCount: (d['itemCount'] as num?)?.toInt() ?? items.length,
      subtotal: (d['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'TL',
      status: _parseStatus(d['status'] as String?),
      deliveryType: d['deliveryType'] as String? ?? 'pickup',
      deliveryAddress: deliveryAddress,
      paymentMethod: d['paymentMethod'] as String? ?? '',
      isPaid: d['isPaid'] as bool? ?? false,
      orderNotes: d['orderNotes'] as String? ?? '',
      estimatedPrepTime: (d['estimatedPrepTime'] as num?)?.toInt() ?? 0,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
      lastInformedAt: d['lastInformedAt'] as Timestamp?,
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _timeAgo(Timestamp? ts, String locale) {
  if (ts == null) return '';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) {
    return switch (locale) {
      'tr' => 'Az önce',
      'ru' => 'Только что',
      _ => 'Just now'
    };
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return switch (locale) {
      'tr' => '${m}dk',
      'ru' => '${m}м',
      _ => '${m}m ago'
    };
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return switch (locale) {
      'tr' => '${h}sa',
      'ru' => '${h}ч',
      _ => '${h}h ago'
    };
  }
  final d = diff.inDays;
  return switch (locale) { 'tr' => '${d}g', 'ru' => '${d}д', _ => '${d}d ago' };
}

String _formatTime(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _formatDate(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${d.day} ${months[d.month - 1]}';
}

String _statusLabel(_OrderStatus status, String locale) {
  switch (status) {
    case _OrderStatus.pending:
      return locale == 'tr'
          ? 'Beklemede'
          : (locale == 'ru' ? 'Ожидает' : 'Pending');
    case _OrderStatus.accepted:
      return locale == 'tr'
          ? 'Kabul Edildi'
          : (locale == 'ru' ? 'Принят' : 'Accepted');
    case _OrderStatus.preparing:
      return locale == 'tr'
          ? 'Hazırlanıyor'
          : (locale == 'ru' ? 'Готовится' : 'Preparing');
    case _OrderStatus.ready:
      return locale == 'tr' ? 'Hazır' : (locale == 'ru' ? 'Готов' : 'Ready');
    case _OrderStatus.out_for_delivery: // ← ADDED
      return locale == 'tr'
          ? 'Teslim Ediliyor'
          : (locale == 'ru' ? 'В пути' : 'Out for Delivery');
    case _OrderStatus.delivered:
      return locale == 'tr'
          ? 'Teslim Edildi'
          : (locale == 'ru' ? 'Доставлен' : 'Delivered');
    case _OrderStatus.rejected:
      return locale == 'tr'
          ? 'Reddedildi'
          : (locale == 'ru' ? 'Отклонён' : 'Rejected');
    case _OrderStatus.cancelled:
      return locale == 'tr'
          ? 'İptal'
          : (locale == 'ru' ? 'Отменён' : 'Cancelled');
  }
}

String _tabLabel(_TabStatus tab, String locale) {
  switch (tab) {
    case _TabStatus.pending:
      return locale == 'tr'
          ? 'Beklemede'
          : (locale == 'ru' ? 'Ожидает' : 'Pending');
    case _TabStatus.accepted:
      return locale == 'tr'
          ? 'Kabul Edildi'
          : (locale == 'ru' ? 'Принятые' : 'Accepted');
    case _TabStatus.delivered:
      return locale == 'tr'
          ? 'Teslim Edildi'
          : (locale == 'ru' ? 'Доставлено' : 'Delivered');
    case _TabStatus.rejected:
      return locale == 'tr'
          ? 'Reddedildi'
          : (locale == 'ru' ? 'Отклонённые' : 'Rejected');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FoodOrdersTab
// ─────────────────────────────────────────────────────────────────────────────

class FoodOrdersTab extends StatefulWidget {
  final String restaurantId;
  const FoodOrdersTab({Key? key, required this.restaurantId}) : super(key: key);

  @override
  State<FoodOrdersTab> createState() => _FoodOrdersTabState();
}

class _FoodOrdersTabState extends State<FoodOrdersTab>
    with AutomaticKeepAliveClientMixin {
  _TabStatus _activeTab = _TabStatus.pending;
  List<_FoodOrder> _orders = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  final Map<String, _OrderStatus> _updatingTo = {};
  // FIX 4: _informingIds removed — _InformCourierBtn now manages its own
  // loading state internally, matching Next.js InformCourierButton behaviour.
  final Set<String> _expandedIds = {};

  StreamSubscription<QuerySnapshot>? _sub;
  DocumentSnapshot? _firstPageLastDoc;

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    _subscribeFirstPage();
  }

  @override
  void didUpdateWidget(FoodOrdersTab old) {
    super.didUpdateWidget(old);
    if (old.restaurantId != widget.restaurantId) {
      _activeTab = _TabStatus.pending;
      _expandedIds.clear();
      _subscribeFirstPage();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Firestore ─────────────────────────────────────────────────────────────

  Query _buildQuery() {
    final statuses = _kTabStatuses[_activeTab]!;

    Query query = FirebaseFirestore.instance
        .collection('orders-food')
        .where('restaurantId', isEqualTo: widget.restaurantId)
        .orderBy('createdAt', descending: true);

    if (statuses.length == 1) {
      query = query.where('status', isEqualTo: _statusToString(statuses.first));
    } else {
      query = query.where('status',
          whereIn: statuses.map(_statusToString).toList());
    }

    return query;
  }

  void _subscribeFirstPage() {
    _sub?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _orders = [];
        _firstPageLastDoc = null;
        _hasMore = true;
      });
    }

    _sub = _buildQuery().limit(_kPageSize).snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _orders = snap.docs.map(_FoodOrder.fromDoc).toList();
          _firstPageLastDoc =
              snap.docs.isNotEmpty ? snap.docs.last : null;
          _hasMore = snap.docs.length >= _kPageSize;
          _loading = false;
          _loadingMore = false;
        });
      },
      onError: (Object e) {
        debugPrint('FoodOrdersTab stream error: $e');
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingMore = false;
          });
        }
      },
    );
  }

  void _switchTab(_TabStatus tab) {
    if (tab == _activeTab) return;
    _sub?.cancel();
    setState(() {
      _activeTab = tab;
      _hasMore = true;
      _loading = true;
      _orders = [];
      _firstPageLastDoc = null;
      _expandedIds.clear();
    });
    _subscribeFirstPage();
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore || _firstPageLastDoc == null) return;
    setState(() => _loadingMore = true);
    _fetchNextPage();
  }

  Future<void> _fetchNextPage() async {
    try {
      final snap = await _buildQuery()
          .startAfterDocument(_firstPageLastDoc!)
          .limit(_kPageSize)
          .get();

      if (!mounted) return;

      final existingIds = _orders.map((o) => o.id).toSet();
      final newOrders = snap.docs
          .map(_FoodOrder.fromDoc)
          .where((o) => !existingIds.contains(o.id))
          .toList();

      setState(() {
        _orders.addAll(newOrders);
        if (snap.docs.isNotEmpty) {
          _firstPageLastDoc = snap.docs.last;
        }
        _hasMore = snap.docs.length >= _kPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('FoodOrdersTab._fetchNextPage error: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _updateStatus(String orderId, _OrderStatus newStatus) async {
    if (_updatingTo.containsKey(orderId)) return;
    setState(() => _updatingTo[orderId] = newStatus);
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateFoodOrderStatus')
          .call({'orderId': orderId, 'newStatus': _statusToString(newStatus)});
    } catch (e) {
      if (mounted) {
        final locale = Localizations.localeOf(context).languageCode;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              locale == 'tr' ? 'Güncelleme başarısız' : 'Failed to update'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _updatingTo.remove(orderId));
    }
  }

  // ── Inform Courier ────────────────────────────────────────────────────────
  // FIX 5: Cooldown errors (resource-exhausted / "wait") now show a warning
  // snackbar and return normally so the button does NOT start an optimistic
  // countdown — matching Next.js informCourier behaviour exactly.
  // All other errors show an error snackbar and re-throw so the button also
  // skips its optimistic countdown.

  Future<void> _informCourier(String orderId) async {
    final locale = Localizations.localeOf(context).languageCode;
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('informFoodCourier')
          .call({'orderId': orderId});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            locale == 'tr'
                ? 'Kurye bildirildi ✓'
                : (locale == 'ru'
                    ? 'Курьеры уведомлены ✓'
                    : 'Couriers notified ✓'),
          ),
          backgroundColor: const Color(0xFF7C3AED),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      // Cooldown / rate-limit error — warn but do NOT re-throw so the button
      // skips its optimistic local countdown (mirrors Next.js resource-exhausted
      // and "wait" check).
      if (e.code == 'resource-exhausted' ||
          (e.message?.toLowerCase().contains('wait') ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            locale == 'tr'
                ? 'Çok hızlı! ${e.message ?? ''}'
                : (locale == 'ru'
                    ? 'Слишком быстро! ${e.message ?? ''}'
                    : 'Too soon! ${e.message ?? ''}'),
          ),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ));
        return; // do NOT re-throw
      }

      // Other errors — show error and re-throw so the button skips countdown.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          locale == 'tr'
              ? 'Bildirim gönderilemedi'
              : (locale == 'ru'
                  ? 'Не удалось уведомить курьеров'
                  : 'Failed to notify couriers'),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ));
      rethrow;
    } catch (e) {
      if (mounted) {
        final locale2 = Localizations.localeOf(context).languageCode;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            locale2 == 'tr'
                ? 'Bildirim gönderilemedi'
                : (locale2 == 'ru'
                    ? 'Не удалось уведомить курьеров'
                    : 'Failed to notify couriers'),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ));
      }
      rethrow;
    }
  }

  void _toggleExpand(String orderId) {
    setState(() {
      if (_expandedIds.contains(orderId)) {
        _expandedIds.remove(orderId);
      } else {
        _expandedIds.add(orderId);
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;

    return Column(
      children: [
        _buildTabBar(isDark, locale),
        Expanded(
          child: _loading
              ? _buildShimmer(isDark)
              : _orders.isEmpty
                  ? _buildEmpty(isDark, locale)
                  : _buildList(isDark, locale),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark, String locale) {
    return Container(
      color: isDark ? const Color(0xFF12121A) : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: _TabStatus.values.map((tab) {
          final isActive = tab == _activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF111827)
                      : (isDark
                          ? Colors.white.withOpacity(0.07)
                          : const Color(0xFFF3F4F6)),
                  borderRadius: BorderRadius.circular(20),
                  border: isActive
                      ? null
                      : Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFFE5E7EB),
                        ),
                ),
                child: Text(
                  _tabLabel(tab, locale),
                  style: GoogleFonts.figtree(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.white
                        : (isDark ? Colors.grey[400] : const Color(0xFF6B7280)),
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildShimmer(bool isDark) {
    final base = isDark ? const Color(0xFF2A2840) : Colors.grey.shade200;
    final highlight = isDark ? const Color(0xFF3C3A55) : Colors.grey.shade100;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Container(height: 12, width: 120, color: Colors.white),
                      const SizedBox(height: 5),
                      Container(height: 10, width: 80, color: Colors.white),
                    ])),
                Container(
                    height: 20,
                    width: 60,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20))),
              ]),
              const SizedBox(height: 10),
              Container(height: 10, color: Colors.white),
              const SizedBox(height: 6),
              Container(height: 10, width: 180, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark, String locale) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 32, color: Color(0xFF4ADE80)),
          ),
          const SizedBox(height: 16),
          Text(
            locale == 'tr'
                ? 'Sipariş yok'
                : (locale == 'ru' ? 'Нет заказов' : 'No orders'),
            style: GoogleFonts.figtree(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            locale == 'tr'
                ? 'Bu kategoride sipariş yok'
                : (locale == 'ru'
                    ? 'В этой категории нет заказов'
                    : 'No orders in this category'),
            style: GoogleFonts.figtree(
              fontSize: 13,
              color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark, String locale) {
    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async => _subscribeFirstPage(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _orders.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _orders.length) return _buildLoadMoreButton(isDark, locale);
          final order = _orders[i];
          return _OrderCard(
            order: order,
            locale: locale,
            isDark: isDark,
            isExpanded: _expandedIds.contains(order.id),
            updatingTo: _updatingTo[order.id],
            onTap: () => _toggleExpand(order.id),
            onUpdateStatus: _updateStatus,
            onInformCourier: _informCourier,
          );
        },
      ),
    );
  }

  Widget _buildLoadMoreButton(bool isDark, String locale) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: _loadingMore ? null : _loadMore,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color:
                    isDark ? const Color(0xFF2D2B42) : const Color(0xFFE5E7EB)),
          ),
          child: Center(
            child: _loadingMore
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.white54 : Colors.grey[400]),
                  )
                : Text(
                    locale == 'tr'
                        ? 'Daha Fazla Yükle'
                        : (locale == 'ru' ? 'Загрузить ещё' : 'Load More'),
                    style: GoogleFonts.figtree(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey[400]
                            : const Color(0xFF6B7280)),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderCard
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final _FoodOrder order;
  final String locale;
  final bool isDark;
  final bool isExpanded;
  final _OrderStatus? updatingTo;
  // FIX 4 (cont): isInforming removed — button manages its own loading state.
  final VoidCallback onTap;
  final Future<void> Function(String, _OrderStatus) onUpdateStatus;
  final Future<void> Function(String) onInformCourier;

  const _OrderCard({
    required this.order,
    required this.locale,
    required this.isDark,
    required this.isExpanded,
    required this.updatingTo,
    required this.onTap,
    required this.onUpdateStatus,
    required this.onInformCourier,
  });

  bool get _isPending => order.status == _OrderStatus.pending;
  bool get _isAccepted => order.status == _OrderStatus.accepted;
  // FIX 6: added _isReady getter to mirror Next.js isReady
  bool get _isReady => order.status == _OrderStatus.ready;
  bool get _isUpdating => updatingTo != null;

  // FIX 7: showActions now mirrors Next.js: isPending || isAccepted || isReady
  bool get _showActions => _isPending || _isAccepted || _isReady;

  @override
  Widget build(BuildContext context) {
    final cfg = _kStatusCfg[order.status]!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF2D2B42) : const Color(0xFFF3F4F6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(cfg),
            _buildItemsSummary(context),
            if (isExpanded) ...[
              _buildOrderNotes(),
              _buildInfoRow(context),
              if (order.deliveryType == 'delivery' &&
                  order.deliveryAddress != null)
                _buildAddressRow(),
              _buildPriceRow(),
              _buildTimestampRow(),
            ],
            if (_showActions) _buildActions(),
            _buildExpandToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_StatusCfg cfg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: cfg.bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(cfg.icon, color: cfg.fg, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(order.buyerName,
                        style: GoogleFonts.figtree(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF111827)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Text(
                      '${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                      style: GoogleFonts.figtree(
                          fontSize: 10,
                          color: isDark
                              ? Colors.grey[500]
                              : const Color(0xFF9CA3AF))),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Text(_formatTime(order.createdAt),
                      style: GoogleFonts.figtree(
                          fontSize: 10,
                          color: isDark
                              ? Colors.grey[500]
                              : const Color(0xFF9CA3AF))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('·',
                        style: GoogleFonts.figtree(
                            fontSize: 10,
                            color: isDark
                                ? Colors.grey[600]
                                : const Color(0xFFD1D5DB))),
                  ),
                  Text(_timeAgo(order.createdAt, locale),
                      style: GoogleFonts.figtree(
                          fontSize: 10,
                          color: isDark
                              ? Colors.grey[500]
                              : const Color(0xFF9CA3AF))),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                  text: TextSpan(children: [
                TextSpan(
                    text: order.totalPrice.toStringAsFixed(2),
                    style: GoogleFonts.figtree(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : const Color(0xFF111827))),
                TextSpan(
                    text: ' ${order.currency}',
                    style: GoogleFonts.figtree(
                        fontSize: 10,
                        color: isDark
                            ? Colors.grey[500]
                            : const Color(0xFF9CA3AF))),
              ])),
              const SizedBox(height: 4),
              _StatusBadge(status: order.status, locale: locale, cfg: cfg),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSummary(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: order.items
            .map((item) => Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF252336)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${item.quantity}x ${item.name}',
                                  style: GoogleFonts.figtree(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1F2937))),
                              if (item.extras.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    item.extras
                                        .map((e) =>
                                            '+${localizeExtra(e.name, l10n)}${e.price > 0 ? ' ${e.price.toStringAsFixed(2)}' : ''}')
                                        .join(', '),
                                    style: GoogleFonts.figtree(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.grey[300]
                                            : const Color(0xFF4B5563)),
                                  ),
                                ),
                            ])),
                        Text(item.itemTotal.toStringAsFixed(2),
                            style: GoogleFonts.figtree(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : const Color(0xFF374151))),
                      ]),
                      if (item.specialNotes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(5)),
                          child: Text(item.specialNotes,
                              style: GoogleFonts.figtree(
                                  fontSize: 10,
                                  color: const Color(0xFFB45309))),
                        ),
                      ],
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildOrderNotes() {
    if (order.orderNotes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.description_outlined,
              size: 15, color: Color(0xFFD97706)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(order.orderNotes,
                  style: GoogleFonts.figtree(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: const Color(0xFFB45309)))),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        _InfoChip(
          icon: order.deliveryType == 'delivery'
              ? Icons.directions_bike_rounded
              : Icons.storefront_rounded,
          label: order.deliveryType == 'delivery'
              ? (locale == 'tr' ? 'Teslimat' : 'Delivery')
              : (locale == 'tr' ? 'Gel Al' : 'Pickup'),
          isDark: isDark,
        ),
        _InfoChip(
          icon: Icons.credit_card_rounded,
          label: order.paymentMethod == 'pay_at_door'
              ? (locale == 'tr' ? 'Kapıda Öde' : 'Pay at Door')
              : order.paymentMethod == 'online'
                  ? (locale == 'tr' ? 'Online' : 'Online')
                  : order.paymentMethod,
          isDark: isDark,
          trailing: order.isPaid
              ? const Icon(Icons.check_circle_rounded,
                  size: 10, color: Color(0xFF16A34A))
              : null,
        ),
        _InfoChip(
          icon: Icons.timer_outlined,
          label: '${order.estimatedPrepTime} ${locale == 'tr' ? 'dk' : 'min'}',
          isDark: isDark,
        ),
        if (order.buyerPhone.isNotEmpty)
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('tel:${order.buyerPhone}');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: order.buyerPhone));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    locale == 'tr' ? 'Numara kopyalandı' : 'Number copied'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ));
            },
            child: _InfoChip(
              icon: Icons.phone_rounded,
              label: order.buyerPhone,
              isDark: isDark,
              tappable: true,
            ),
          ),
      ]),
    );
  }

  Widget _buildAddressRow() {
    final da = order.deliveryAddress!;
    if (da.addressLine1.isEmpty && da.city.isEmpty) {
      return const SizedBox.shrink();
    }
    final lines = <String>[
      da.addressLine1,
      if (da.addressLine2.isNotEmpty) da.addressLine2,
      if (da.city.isNotEmpty) da.city,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.location_on_outlined,
            size: 15,
            color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Expanded(
            child: Text(lines.join('\n'),
                style: GoogleFonts.figtree(
                    fontSize: 12,
                    color:
                        isDark ? Colors.grey[400] : const Color(0xFF6B7280)))),
      ]),
    );
  }

  Widget _buildPriceRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(spacing: 12, children: [
        Text(
            '${locale == 'tr' ? 'Ara toplam' : 'Subtotal'}: ${order.subtotal.toStringAsFixed(2)}',
            style: GoogleFonts.figtree(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF))),
        if (order.deliveryFee > 0)
          Text(
              '${locale == 'tr' ? 'Teslimat' : 'Delivery'}: ${order.deliveryFee.toStringAsFixed(2)}',
              style: GoogleFonts.figtree(
                  fontSize: 13,
                  color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF))),
        Text(
            '${locale == 'tr' ? 'Toplam' : 'Total'}: ${order.totalPrice.toStringAsFixed(2)} ${order.currency}',
            style: GoogleFonts.figtree(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[300] : const Color(0xFF374151))),
      ]),
    );
  }

  Widget _buildTimestampRow() {
    final created =
        '${_formatDate(order.createdAt)} ${_formatTime(order.createdAt)}';
    final showUpdated = order.updatedAt != null &&
        order.updatedAt!.seconds != order.createdAt?.seconds;
    // FIX 8: Show lastInformedAt in footer — mirrors Next.js lastInformedAt display.
    final showInformed = order.lastInformedAt != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Text(
            showUpdated
                ? '$created · ${locale == 'tr' ? 'güncellendi' : 'updated'} ${_formatTime(order.updatedAt)}'
                : created,
            style: GoogleFonts.figtree(
                fontSize: 12,
                color: isDark ? Colors.grey[600] : const Color(0xFFD1D5DB)),
            textAlign: TextAlign.center,
          ),
          if (showInformed)
            Text(
              '· ${locale == 'tr' ? 'Kurye bildirildi' : 'Courier informed'} ${_formatTime(order.lastInformedAt)}',
              style: GoogleFonts.figtree(
                  fontSize: 12, color: const Color(0xFFC4B5FD)), // violet-300
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(children: [
        // ── PENDING: Accept + Reject ─────────────────────────────────────
        if (_isPending) ...[
          Expanded(
              child: _ActionBtn(
            label: locale == 'tr' ? 'Kabul Et' : 'Accept',
            icon: Icons.check_rounded,
            bg: const Color(0xFF22C55E),
            fg: Colors.white,
            loading: _isUpdating && updatingTo == _OrderStatus.accepted,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _OrderStatus.accepted),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: _ActionBtn(
            label: locale == 'tr' ? 'Reddet' : 'Reject',
            icon: Icons.close_rounded,
            bg: const Color(0xFFFEF2F2),
            fg: const Color(0xFFDC2626),
            loading: _isUpdating && updatingTo == _OrderStatus.rejected,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _OrderStatus.rejected),
          )),
        ],

        // ── ACCEPTED: Mark As Ready + Inform Courier (delivery only) + Reject
        // FIX 9: primary action changed from "Mark Delivered" → "Mark Ready"
        // to match Next.js (accepted → ready, not accepted → delivered).
        if (_isAccepted) ...[
          Expanded(
              child: _ActionBtn(
            label: locale == 'tr' ? 'Hazır İşaretle' : 'Mark As Ready',
            icon: Icons.inventory_2_outlined,
            bg: const Color(0xFF22C55E),
            fg: Colors.white,
            loading: _isUpdating && updatingTo == _OrderStatus.ready,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _OrderStatus.ready),
          )),
          if (order.deliveryType == 'delivery') ...[
            const SizedBox(width: 8),
            _InformCourierBtn(
              lastInformedAt: order.lastInformedAt,
              locale: locale,
              onTap: () => onInformCourier(order.id),
            ),
          ],
          const SizedBox(width: 8),
          _ActionBtn(
            label: locale == 'tr' ? 'Reddet' : 'Reject',
            icon: Icons.close_rounded,
            bg: const Color(0xFFFEF2F2),
            fg: const Color(0xFFDC2626),
            loading: _isUpdating && updatingTo == _OrderStatus.rejected,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _OrderStatus.rejected),
          ),
        ],

        // ── READY: "Waiting for cargo" text only — no button.
        // FIX 10: mirrors Next.js isReady block which shows text, not a button.
        if (_isReady)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                locale == 'tr'
                    ? 'Kargo bekleniyor'
                    : (locale == 'ru'
                        ? 'Ожидание курьера'
                        : 'Waiting for cargo'),
                style: GoogleFonts.figtree(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildExpandToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
          color: isDark ? const Color(0xFF2D2B42) : const Color(0xFFF3F4F6),
        )),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          isExpanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: isDark ? Colors.grey[600] : const Color(0xFFD1D5DB),
        ),
        const SizedBox(width: 4),
        Text(
          isExpanded
              ? (locale == 'tr' ? 'Daha az' : 'Less detail')
              : (locale == 'tr' ? 'Daha fazla' : 'More detail'),
          style: GoogleFonts.figtree(
              fontSize: 10,
              color: isDark ? Colors.grey[600] : const Color(0xFFD1D5DB)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InformCourierBtn — self-contained cooldown countdown
// ─────────────────────────────────────────────────────────────────────────────

class _InformCourierBtn extends StatefulWidget {
  final Timestamp? lastInformedAt;
  final String locale;
  // FIX 11: onTap is now Future<void> Function() so the button can await it
  // and start its own optimistic countdown — matching Next.js handleClick.
  // The external loading bool is gone; the button owns its own _loading state.
  final Future<void> Function() onTap;

  const _InformCourierBtn({
    required this.lastInformedAt,
    required this.locale,
    required this.onTap,
  });

  @override
  State<_InformCourierBtn> createState() => _InformCourierBtnState();
}

class _InformCourierBtnState extends State<_InformCourierBtn> {
  bool _loading = false;
  int _cooldownSec = 0;
  Timer? _timer;

  int _calcRemaining() {
    if (widget.lastInformedAt == null) return 0;
    final elapsed = DateTime.now()
        .difference(widget.lastInformedAt!.toDate())
        .inMilliseconds;
    final rem = _kInformCooldownMs - elapsed;
    return rem > 0 ? (rem / 1000).ceil() : 0;
  }

  // Starts a Firestore-backed countdown from lastInformedAt.
  void _startFirestoreTimer() {
    _timer?.cancel();
    final rem = _calcRemaining();
    if (rem <= 0) {
      if (mounted) setState(() => _cooldownSec = 0);
      return;
    }
    if (mounted) setState(() => _cooldownSec = rem);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = _calcRemaining();
      if (mounted) setState(() => _cooldownSec = r);
      if (r <= 0) _timer?.cancel();
    });
  }

  // FIX 12: Starts an optimistic local countdown immediately after a
  // successful call — mirrors Next.js InformCourierButton handleClick which
  // sets its own endAt timer before Firestore propagates lastInformedAt.
  void _startOptimisticTimer() {
    _timer?.cancel();
    final endMs = DateTime.now().millisecondsSinceEpoch + _kInformCooldownMs;
    final initial = ((_kInformCooldownMs) / 1000).ceil();
    if (mounted) setState(() => _cooldownSec = initial);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rem = endMs - DateTime.now().millisecondsSinceEpoch;
      final secs = rem > 0 ? (rem / 1000).ceil() : 0;
      if (mounted) setState(() => _cooldownSec = secs);
      if (secs <= 0) _timer?.cancel();
    });
  }

  @override
  void initState() {
    super.initState();
    _startFirestoreTimer();
  }

  @override
  void didUpdateWidget(_InformCourierBtn old) {
    super.didUpdateWidget(old);
    // When Firestore delivers a new lastInformedAt, switch to Firestore-backed
    // countdown (which will naturally sync if it's more accurate).
    if (old.lastInformedAt != widget.lastInformedAt) {
      _startFirestoreTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_loading || _cooldownSec > 0) return;
    setState(() => _loading = true);
    try {
      await widget.onTap();
      // Success — start optimistic countdown immediately (matches Next.js).
      _startOptimisticTimer();
    } catch (_) {
      // Error or cooldown warning already handled + toasted by parent.
      // Do NOT start countdown (matches Next.js re-throw branch).
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onCooldown = _cooldownSec > 0;
    final disabled = _loading || onCooldown;

    final label = onCooldown
        ? '${(_cooldownSec ~/ 60).toString().padLeft(2, '0')}:${(_cooldownSec % 60).toString().padLeft(2, '0')}'
        : (widget.locale == 'tr'
            ? 'Kuryeyi Bildir'
            : (widget.locale == 'ru' ? 'Вызвать курьера' : 'Inform Courier'));

    return GestureDetector(
      onTap: disabled ? null : _handleTap,
      child: AnimatedOpacity(
        opacity: disabled ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFF3F4F6) : const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  disabled ? const Color(0xFFE5E7EB) : const Color(0xFFDDD6FE),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _loading
                ? const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF7C3AED))),
                  )
                : Icon(
                    onCooldown
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_outlined,
                    size: 13,
                    color: disabled
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF7C3AED),
                  ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.figtree(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: disabled
                    ? const Color(0xFF9CA3AF)
                    : const Color(0xFF7C3AED),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final _OrderStatus status;
  final String locale;
  final _StatusCfg cfg;
  const _StatusBadge(
      {required this.status, required this.locale, required this.cfg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: cfg.bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: cfg.dot)),
          const SizedBox(width: 4),
          Text(_statusLabel(status, locale),
              style: GoogleFonts.figtree(
                  fontSize: 9, fontWeight: FontWeight.w700, color: cfg.fg)),
        ]),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Widget? trailing;
  final bool tappable;
  const _InfoChip(
      {required this.icon,
      required this.label,
      required this.isDark,
      this.trailing,
      this.tappable = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: tappable
              ? (isDark
                  ? Colors.white.withOpacity(0.07)
                  : const Color(0xFFF3F4F6))
              : (isDark
                  ? Colors.white.withOpacity(0.05)
                  : const Color(0xFFF9FAFB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 13,
              color: isDark ? Colors.grey[400] : const Color(0xFF9CA3AF)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.figtree(
                  fontSize: 12,
                  fontWeight: tappable ? FontWeight.w600 : FontWeight.normal,
                  color: isDark ? Colors.grey[300] : const Color(0xFF6B7280))),
          if (trailing != null) ...[const SizedBox(width: 3), trailing!],
        ]),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.bg,
      required this.fg,
      required this.loading,
      required this.enabled,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: loading
                  ? [
                      SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(fg)))
                    ]
                  : [
                      Icon(icon, size: 13, color: fg),
                      const SizedBox(width: 5),
                      Text(label,
                          style: GoogleFonts.figtree(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: fg)),
                    ],
            ),
          ),
        ),
      );
}
