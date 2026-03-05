import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Re-use all models, enums, helpers, and sub-widgets from food_orders.dart
// They are defined here as private to this file, mirroring the standalone page.
// The only difference: FoodOrdersTab has no Scaffold/AppBar — it is designed
// to live inside a TabBarView.
// ─────────────────────────────────────────────────────────────────────────────

const _kPageSize = 15;

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _OrderStatus {
  pending,
  accepted,
  rejected,
  preparing,
  ready,
  delivered,
  cancelled,
}

enum _TabStatus { pending, accepted, delivered, rejected }

const _kTabStatuses = <_TabStatus, List<_OrderStatus>>{
  _TabStatus.pending: [_OrderStatus.pending],
  _TabStatus.accepted: [
    _OrderStatus.accepted,
    _OrderStatus.preparing,
    _OrderStatus.ready,
  ],
  _TabStatus.delivered: [_OrderStatus.delivered],
  _TabStatus.rejected: [_OrderStatus.rejected, _OrderStatus.cancelled],
};

const _kNextStatus = <_OrderStatus, _OrderStatus>{
  _OrderStatus.ready: _OrderStatus.delivered,
};

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
// FoodOrdersTab — no Scaffold, designed to live inside a TabBarView
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
  int _currentLimit = _kPageSize;

  final Map<String, _OrderStatus> _updatingTo = {};
  final Set<String> _expandedIds = {};

  StreamSubscription<QuerySnapshot>? _sub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(FoodOrdersTab old) {
    super.didUpdateWidget(old);
    if (old.restaurantId != widget.restaurantId) {
      _activeTab = _TabStatus.pending;
      _currentLimit = _kPageSize;
      _expandedIds.clear();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Firestore ─────────────────────────────────────────────────────────────

  void _subscribe({bool isLoadMore = false}) {
    _sub?.cancel();
    if (mounted) {
      setState(() {
        // Only show full shimmer on fresh loads, not on load-more
        if (!isLoadMore) {
          _loading = true;
          _orders = [];
        }
      });
    }

    final statuses = _kTabStatuses[_activeTab]!;

    Query query = FirebaseFirestore.instance
        .collection('orders-food')
        .where('restaurantId', isEqualTo: widget.restaurantId)
        .orderBy('createdAt', descending: true)
        .limit(_currentLimit);

    if (statuses.length == 1) {
      query = query.where('status', isEqualTo: _statusToString(statuses.first));
    } else {
      query = query.where('status',
          whereIn: statuses.map(_statusToString).toList());
    }

    _sub = query.snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _orders = snap.docs.map(_FoodOrder.fromDoc).toList();
          _hasMore = snap.size >= _currentLimit;
          _loading = false;
          _loadingMore = false;
        });
      },
      onError: (Object e) {
        debugPrint('FoodOrdersTab stream error: $e');
        if (mounted)
          setState(() {
            _loading = false;
            _loadingMore = false;
          });
      },
    );
  }

  void _switchTab(_TabStatus tab) {
    if (tab == _activeTab) return;
    _sub?.cancel();
    setState(() {
      _activeTab = tab;
      _currentLimit = _kPageSize;
      _hasMore = true;
      _loading = true;
      _orders = [];
      _expandedIds.clear();
    });
    _subscribe();
  }

  void _loadMore() {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _currentLimit += _kPageSize;
    });
    _subscribe(isLoadMore: true); // ← don't clear orders
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

  // ── Status filter tabs ────────────────────────────────────────────────────

  Widget _buildTabBar(bool isDark, String locale) {
    return Container(
      color: isDark ? const Color(0xFF12121A) : Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: _TabStatus.values.map((tab) {
          final isActive = tab == _activeTab;
          final count = isActive ? _orders.length : 0;
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _tabLabel(tab, locale),
                        style: GoogleFonts.figtree(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : (isDark
                                  ? Colors.grey[400]
                                  : const Color(0xFF6B7280)),
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (isActive && count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _hasMore ? '$count+' : '$count',
                          style: GoogleFonts.figtree(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Shimmer ───────────────────────────────────────────────────────────────

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

  // ── Empty ─────────────────────────────────────────────────────────────────

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

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList(bool isDark, String locale) {
    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async => _subscribe(),
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
  final VoidCallback onTap;
  final Future<void> Function(String, _OrderStatus) onUpdateStatus;

  const _OrderCard({
    required this.order,
    required this.locale,
    required this.isDark,
    required this.isExpanded,
    required this.updatingTo,
    required this.onTap,
    required this.onUpdateStatus,
  });

  bool get _isPending => order.status == _OrderStatus.pending;
  bool get _isAccepted => order.status == _OrderStatus.accepted;
  bool get _isUpdating => updatingTo != null;
  _OrderStatus? get _nextStatus => _kNextStatus[order.status];
  bool get _showActions => _isPending || _isAccepted || _nextStatus != null;

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
            _buildItemsSummary(),
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

  Widget _buildItemsSummary() {
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
                            child: Row(children: [
                          Text('${item.quantity}x ${item.name}',
                              style: GoogleFonts.figtree(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1F2937))),
                          if (item.extras.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text(
                                    '(${item.extras.map((e) => '+${e.name}${e.price > 0 ? ' ${e.price.toStringAsFixed(2)}' : ''}').join(', ')})',
                                    style: GoogleFonts.figtree(
                                        fontSize: 10,
                                        color: isDark
                                            ? Colors.grey[500]
                                            : const Color(0xFF9CA3AF)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                          ],
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
              size: 13, color: Color(0xFFD97706)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(order.orderNotes,
                  style: GoogleFonts.figtree(
                      fontSize: 11,
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
    final addr = order.deliveryAddress!.formatted;
    if (addr.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.location_on_outlined,
            size: 13,
            color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Expanded(
            child: Text(addr,
                style: GoogleFonts.figtree(
                    fontSize: 10,
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
                fontSize: 11,
                color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF))),
        if (order.deliveryFee > 0)
          Text(
              '${locale == 'tr' ? 'Teslimat' : 'Delivery'}: ${order.deliveryFee.toStringAsFixed(2)}',
              style: GoogleFonts.figtree(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF))),
        Text(
            '${locale == 'tr' ? 'Toplam' : 'Total'}: ${order.totalPrice.toStringAsFixed(2)} ${order.currency}',
            style: GoogleFonts.figtree(
                fontSize: 11,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        showUpdated
            ? '$created · ${locale == 'tr' ? 'güncellendi' : 'updated'} ${_formatTime(order.updatedAt)}'
            : created,
        style: GoogleFonts.figtree(
            fontSize: 10,
            color: isDark ? Colors.grey[600] : const Color(0xFFD1D5DB)),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(children: [
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
        if (_isAccepted) ...[
          Expanded(
              child: _ActionBtn(
            label: locale == 'tr' ? 'Teslim Edildi' : 'Mark Delivered',
            icon: Icons.check_circle_outline_rounded,
            bg: const Color(0xFF22C55E),
            fg: Colors.white,
            loading: _isUpdating && updatingTo == _OrderStatus.delivered,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _OrderStatus.delivered),
          )),
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
        if (!_isPending && !_isAccepted && _nextStatus != null)
          Expanded(
              child: _ActionBtn(
            label: _nextStatus == _OrderStatus.ready
                ? (locale == 'tr' ? 'Hazır İşaretle' : 'Mark Ready')
                : (locale == 'tr' ? 'Teslim Edildi' : 'Mark Delivered'),
            icon: _nextStatus == _OrderStatus.ready
                ? Icons.inventory_2_outlined
                : Icons.check_circle_outline_rounded,
            bg: _nextStatus == _OrderStatus.delivered
                ? const Color(0xFF374151)
                : const Color(0xFF22C55E),
            fg: Colors.white,
            loading: _isUpdating && updatingTo == _nextStatus,
            enabled: !_isUpdating,
            onTap: () => onUpdateStatus(order.id, _nextStatus!),
          )),
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
              size: 11,
              color: isDark ? Colors.grey[400] : const Color(0xFF9CA3AF)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.figtree(
                  fontSize: 10,
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
