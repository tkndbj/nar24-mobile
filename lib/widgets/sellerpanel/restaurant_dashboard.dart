import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../screens/CARGO-FOOD-PANEL/receipt_scanner.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../utils/food_localization.dart';
import './courier_choice_modal.dart';
import './switch_courier_button.dart';

// ─── Order status ─────────────────────────────────────────────────────────────

enum _OrderStatus {
  pending,
  accepted,
  rejected,
  preparing,
  ready,
  delivered,
  cancelled,
}

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

// ─── Data models ──────────────────────────────────────────────────────────────

class _OrderExtra {
  final String name;
  final num price;
  final int quantity;
  const _OrderExtra({
    required this.name,
    required this.price,
    required this.quantity,
  });
}

class _OrderItem {
  final String name;
  final int quantity;
  final List<_OrderExtra> extras;
  final String description;
  final String specialNotes;
  const _OrderItem({
    required this.name,
    required this.quantity,
    required this.extras,
    required this.description,
    required this.specialNotes,
  });
}

class _PendingOrder {
  final String id;
  final String buyerName;
  final List<_OrderItem> items;
  final double totalPrice;
  final String currency;
  final _OrderStatus status;
  final Timestamp? createdAt;
  final String? courierType;
  const _PendingOrder({
    required this.id,
    required this.buyerName,
    required this.items,
    required this.totalPrice,
    required this.currency,
    required this.status,
    this.courierType,
    this.createdAt,
  });

  factory _PendingOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'] as List? ?? [];
    return _PendingOrder(
      id: doc.id,
      buyerName: d['buyerName'] as String? ?? '',
      items: rawItems.map((raw) {
        final item = raw as Map<String, dynamic>;
        final rawExtras = item['extras'] as List? ?? [];
        return _OrderItem(
          name: item['name'] as String? ?? '',
          quantity: (item['quantity'] as num?)?.toInt() ?? 1,
          description: item['description'] as String? ?? '',
          specialNotes: item['specialNotes'] as String? ?? '',
          extras: rawExtras.map((e) {
            final ex = e as Map<String, dynamic>;
            return _OrderExtra(
              name: ex['name'] as String? ?? '',
              price: ex['price'] as num? ?? 0,
              quantity: (ex['quantity'] as num?)?.toInt() ?? 1,
            );
          }).toList(),
        );
      }).toList(),
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0.0,
      currency: d['currency'] as String? ?? 'TL',
      status: _parseStatus(d['status'] as String?),
      courierType: d['courierType'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

class _RestaurantInfo {
  final bool isActive;
  final List<String> workingDays;
  final String openTime;
  final String closeTime;

  const _RestaurantInfo({
    required this.isActive,
    required this.workingDays,
    required this.openTime,
    required this.closeTime,
  });
}

// ─── Status visual config ─────────────────────────────────────────────────────

class _StatusCfg {
  final Color bg;
  final Color fg;
  final IconData icon;
  const _StatusCfg({required this.bg, required this.fg, required this.icon});
}

const _kStatusCfg = <_OrderStatus, _StatusCfg>{
  _OrderStatus.pending: _StatusCfg(
      bg: Color(0xFFFFFBEB),
      fg: Color(0xFFB45309),
      icon: Icons.schedule_rounded),
  _OrderStatus.accepted: _StatusCfg(
      bg: Color(0xFFF0FDFA),
      fg: Color(0xFF0F766E),
      icon: Icons.check_circle_outline_rounded),
  _OrderStatus.rejected: _StatusCfg(
      bg: Color(0xFFFFF1F2),
      fg: Color(0xFFDC2626),
      icon: Icons.cancel_outlined),
  _OrderStatus.preparing: _StatusCfg(
      bg: Color(0xFFEFF6FF),
      fg: Color(0xFF1D4ED8),
      icon: Icons.soup_kitchen_outlined),
  _OrderStatus.ready: _StatusCfg(
      bg: Color(0xFFF0FDF4),
      fg: Color(0xFF15803D),
      icon: Icons.inventory_2_outlined),
  _OrderStatus.delivered: _StatusCfg(
      bg: Color(0xFFF9FAFB),
      fg: Color(0xFF6B7280),
      icon: Icons.check_circle_outline_rounded),
  _OrderStatus.cancelled: _StatusCfg(
      bg: Color(0xFFFFF1F2),
      fg: Color(0xFFDC2626),
      icon: Icons.cancel_outlined),
};

// ─── Open/closed status ───────────────────────────────────────────────────────

enum _OpenStatus { open, closedInactive, closedOffDay, closedOffHours }

// Dart weekday: Mon=1…Sun=7.  JS-style index (Sun=0): weekday % 7
const _kDayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

_OpenStatus _computeOpenStatus(_RestaurantInfo info) {
  if (!info.isActive) return _OpenStatus.closedInactive;

  final now = DateTime.now();
  final todayName = _kDayNames[now.weekday % 7];

  if (info.workingDays.isNotEmpty && !info.workingDays.contains(todayName)) {
    return _OpenStatus.closedOffDay;
  }

  if (info.openTime.isNotEmpty && info.closeTime.isNotEmpty) {
    final nowMins = now.hour * 60 + now.minute;
    final oParts = info.openTime.split(':');
    final cParts = info.closeTime.split(':');
    final openMins = int.parse(oParts[0]) * 60 + int.parse(oParts[1]);
    final closeMins = int.parse(cParts[0]) * 60 + int.parse(cParts[1]);

    if (closeMins > openMins) {
      // Normal range e.g. 09:00–22:00
      if (nowMins < openMins || nowMins >= closeMins) {
        return _OpenStatus.closedOffHours;
      }
    } else if (closeMins < openMins) {
      // Overnight range e.g. 20:00–04:00
      if (nowMins < openMins && nowMins >= closeMins) {
        return _OpenStatus.closedOffHours;
      }
    }
  }

  return _OpenStatus.open;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _kDayShort = <String, Map<String, String>>{
  'Monday': {'en': 'Mon', 'tr': 'Pzt', 'ru': 'Пн'},
  'Tuesday': {'en': 'Tue', 'tr': 'Sal', 'ru': 'Вт'},
  'Wednesday': {'en': 'Wed', 'tr': 'Çar', 'ru': 'Ср'},
  'Thursday': {'en': 'Thu', 'tr': 'Per', 'ru': 'Чт'},
  'Friday': {'en': 'Fri', 'tr': 'Cum', 'ru': 'Пт'},
  'Saturday': {'en': 'Sat', 'tr': 'Cmt', 'ru': 'Сб'},
  'Sunday': {'en': 'Sun', 'tr': 'Paz', 'ru': 'Вс'},
};

String _timeAgo(Timestamp? ts, String locale) {
  if (ts == null) return '';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) {
    return switch (locale) {
      'tr' => 'Az önce',
      'ru' => 'Только что',
      _ => 'Just now',
    };
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return switch (locale) { 'tr' => '${m}dk', 'ru' => '${m}м', _ => '${m}m' };
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return switch (locale) { 'tr' => '${h}sa', 'ru' => '${h}ч', _ => '${h}h' };
  }
  final d = diff.inDays;
  return switch (locale) { 'tr' => '${d}g', 'ru' => '${d}д', _ => '${d}d' };
}

// ─── Pagination ──────────────────────────────────────────────────────────────

const _kPageSize = 20;

// ─────────────────────────────────────────────────────────────────────────────
// RestaurantDashboardTab
// ─────────────────────────────────────────────────────────────────────────────

class RestaurantDashboardTab extends StatefulWidget {
  final String restaurantId;
  const RestaurantDashboardTab({Key? key, required this.restaurantId})
      : super(key: key);
  @override
  State<RestaurantDashboardTab> createState() => _RestaurantDashboardTabState();
}

class _RestaurantDashboardTabState extends State<RestaurantDashboardTab>
    with AutomaticKeepAliveClientMixin {
  // ── Restaurant data ───────────────────────────────────────────────────────
  String? _restaurantId;
  String? _restaurantName;
  _RestaurantInfo? _restaurantInfo;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRestaurant(widget.restaurantId);
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadRestaurant(String restaurantId) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final restSnap = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(restaurantId)
          .get();

      if (!mounted) return;
      if (!restSnap.exists) {
        _setEmpty();
        return;
      }

      final d = restSnap.data()!;
      final wh = d['workingHours'] as Map<String, dynamic>? ?? {};

      setState(() {
        _restaurantId = restaurantId;
        _restaurantName = d['name'] as String? ?? '';
        _restaurantInfo = _RestaurantInfo(
          isActive: d['isActive'] != false,
          workingDays: (d['workingDays'] as List?)?.cast<String>() ?? [],
          openTime: wh['open'] as String? ?? '',
          closeTime: wh['close'] as String? ?? '',
        );
        _loading = false;
      });
    } catch (e) {
      debugPrint('RestaurantDashboardTab._loadRestaurant: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _setEmpty() {
    if (mounted) {
      setState(() {
        _loading = false;
        _restaurantId = null;
      });
    }
  }

  // ── Greeting ──────────────────────────────────────────────────────────────

  String _greeting(AppLocalizations l10n) {
    final h = DateTime.now().hour;
    if (h < 12) return l10n.restaurantDashboardGreetingMorning;
    if (h < 18) return l10n.restaurantDashboardGreetingAfternoon;
    return l10n.restaurantDashboardGreetingEvening;
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;

    if (_loading) return _buildShimmer(isDark);
    if (_failed) return _buildError(isDark, l10n);
    if (_restaurantId == null) return _buildNoRestaurant(isDark, l10n);
    return _buildDashboard(isDark, l10n, locale);
  }

  // ── Shimmer ───────────────────────────────────────────────────────────────

  Widget _buildShimmer(bool isDark) {
    final base = isDark ? const Color(0xFF2A2840) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C3A55) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shimmerBox(14, 130),
            const SizedBox(height: 8),
            _shimmerBox(26, 210),
            const SizedBox(height: 24),
            _shimmerBox(10, 160),
            const SizedBox(height: 12),
            ...List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox(double h, double w) => Container(
        height: h,
        width: w,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: Color(0xFFEF4444), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.restaurantDashboardFetchFailedTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.restaurantDashboardFetchFailedMessage,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _loadRestaurant(widget.restaurantId),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                l10n.restaurantDashboardRetry,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEA580C),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── No restaurant ─────────────────────────────────────────────────────────

  Widget _buildNoRestaurant(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.restaurant_rounded,
                  color: Color(0xFFEA580C), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.restaurantDashboardNoRestaurantTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.restaurantDashboardNoRestaurantDescription,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(RestaurantDashboardTab old) {
    super.didUpdateWidget(old);
    if (old.restaurantId != widget.restaurantId) {
      _loadRestaurant(widget.restaurantId);
    }
  }

  // ── Main dashboard ────────────────────────────────────────────────────────

  Widget _buildDashboard(bool isDark, AppLocalizations l10n, String locale) {
    return _PendingOrdersSection(
      restaurantId: _restaurantId!,
      locale: locale,
      l10n: l10n,
      isDark: isDark,
      onRefresh: () => _loadRestaurant(widget.restaurantId),
      headerBuilder: () => _buildGreetingSection(isDark, l10n, locale),
      sectionLabel:
          _sectionLabel(l10n.restaurantDashboardPendingOrdersTitle, isDark),
      viewAllLabel: GestureDetector(
        onTap: () => context.push('/orders_food'),
        child: Text(
          l10n.restaurantDashboardViewAll,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFEA580C),
          ),
        ),
      ),
    );
  }

  void _openReceiptScanner(BuildContext context) {
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ReceiptScanScreen.forRestaurant(
          restaurantId: _restaurantId!,
          restaurantName: _restaurantName,
        ),
      ),
    );
  }

  // ── Greeting section ──────────────────────────────────────────────────────

  // In _buildGreetingSection, fix the layout:
  Widget _buildGreetingSection(
      bool isDark, AppLocalizations l10n, String locale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _greeting(l10n),
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _restaurantName ?? '',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_restaurantInfo != null) ...[
              const SizedBox(width: 8),
              _OpenStatusBadge(info: _restaurantInfo!, l10n: l10n),
            ],
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _openReceiptScanner(context),
              icon: const Icon(Icons.document_scanner_rounded, size: 22),
              tooltip: 'Fiş Tara',
              color: const Color(0xFFEA580C),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        if (_restaurantInfo != null)
          _ScheduleBadges(info: _restaurantInfo!, locale: locale),
      ],
    );
  }

  Widget _sectionLabel(String text, bool isDark) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? Colors.grey[500] : const Color(0xFF9CA3AF),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Open status badge
// ─────────────────────────────────────────────────────────────────────────────

class _OpenStatusBadge extends StatelessWidget {
  final _RestaurantInfo info;
  final AppLocalizations l10n;
  const _OpenStatusBadge({required this.info, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final status = _computeOpenStatus(info);
    final isOpen = status == _OpenStatus.open;

    final String label = switch (status) {
      _OpenStatus.open => l10n.restaurantDashboardStatusOpen,
      _OpenStatus.closedInactive =>
        l10n.restaurantDashboardStatusClosedInactive,
      _OpenStatus.closedOffDay => l10n.restaurantDashboardStatusClosedOffDay,
      _OpenStatus.closedOffHours =>
        l10n.restaurantDashboardStatusClosedOffHours,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isOpen ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOpen ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isOpen ? const Color(0xFF15803D) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule badges (working days + hours)
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleBadges extends StatelessWidget {
  final _RestaurantInfo info;
  final String locale;
  const _ScheduleBadges({required this.info, required this.locale});

  String _dayLabel(String day) =>
      _kDayShort[day]?[locale] ?? _kDayShort[day]?['en'] ?? day;

  @override
  Widget build(BuildContext context) {
    if (info.workingDays.isEmpty && info.openTime.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (info.workingDays.isNotEmpty)
            _Badge(
              icon: Icons.calendar_today_rounded,
              label: info.workingDays.map(_dayLabel).join(', '),
              bg: const Color(0xFFFFF7ED),
              fg: const Color(0xFFEA580C),
            ),
          if (info.openTime.isNotEmpty && info.closeTime.isNotEmpty)
            _Badge(
              icon: Icons.access_time_rounded,
              label: '${info.openTime} – ${info.closeTime}',
              bg: const Color(0xFFEFF6FF),
              fg: const Color(0xFF1D4ED8),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _Badge(
      {required this.icon,
      required this.label,
      required this.bg,
      required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _PendingOrdersSection – paginated Firestore pending orders
// ─────────────────────────────────────────────────────────────────────────────

class _PendingOrdersSection extends StatefulWidget {
  final String restaurantId;
  final String locale;
  final AppLocalizations l10n;
  final bool isDark;
  final Future<void> Function() onRefresh;
  final Widget Function() headerBuilder;
  final Widget sectionLabel;
  final Widget viewAllLabel;

  const _PendingOrdersSection({
    required this.restaurantId,
    required this.locale,
    required this.l10n,
    required this.isDark,
    required this.onRefresh,
    required this.headerBuilder,
    required this.sectionLabel,
    required this.viewAllLabel,
  });

  @override
  State<_PendingOrdersSection> createState() => _PendingOrdersSectionState();
}

class _PendingOrdersSectionState extends State<_PendingOrdersSection> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<QuerySnapshot>? _firstPageSub;
  List<_PendingOrder> _orders = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  final Map<String, String> _updatingTo = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _subscribeFirstPage(widget.restaurantId);
  }

  @override
  void didUpdateWidget(_PendingOrdersSection old) {
    super.didUpdateWidget(old);
    if (old.restaurantId != widget.restaurantId) {
      _subscribeFirstPage(widget.restaurantId);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _firstPageSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) {
      _loadNextPage();
    }
  }

  // ── First page: real-time stream for live updates ─────────────────────────

  void _subscribeFirstPage(String restaurantId) {
    _firstPageSub?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _orders = [];
        _lastDoc = null;
        _hasMore = true;
      });
    }

    _firstPageSub = FirebaseFirestore.instance
        .collection('orders-food')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(_kPageSize)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _orders = snap.docs.map(_PendingOrder.fromDoc).toList();
          _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
          _hasMore = snap.docs.length >= _kPageSize;
          _loading = false;
        });
      },
      onError: (Object e) {
        debugPrint('_PendingOrdersSection stream error: $e');
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  // ── Next pages: one-shot fetch ────────────────────────────────────────────

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders-food')
          .where('restaurantId', isEqualTo: widget.restaurantId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_kPageSize)
          .get();

      if (!mounted) return;

      final newOrders = snap.docs.map(_PendingOrder.fromDoc).toList();
      // Deduplicate (first-page stream may have shifted)
      final existingIds = _orders.map((o) => o.id).toSet();
      final unique =
          newOrders.where((o) => !existingIds.contains(o.id)).toList();

      setState(() {
        _orders.addAll(unique);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasMore = snap.docs.length >= _kPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('_PendingOrdersSection._loadNextPage: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> _handleRefresh() async {
    _subscribeFirstPage(widget.restaurantId);
    await widget.onRefresh();
  }

  // ── Cloud Function call ───────────────────────────────────────────────────

// Generic status update — used for reject (and anything else non-accept)
  Future<void> _updateStatus(String orderId, String newStatus) async {
    if (_updatingTo.containsKey(orderId)) return;
    setState(() => _updatingTo[orderId] = newStatus);

    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateFoodOrderStatus')
          .call({'orderId': orderId, 'newStatus': newStatus});
    } catch (e) {
      debugPrint('_PendingOrdersSection._updateStatus: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.l10n.restaurantDashboardUpdateFailed),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingTo.remove(orderId));
    }
  }

// Accept flow — shows the courier choice sheet first, then calls the CF
// with the selected courierType.
  Future<void> _acceptOrder(String orderId) async {
    if (_updatingTo.containsKey(orderId)) return;

    final choice = await showCourierChoiceSheet(
      context: context,
      restaurantId: widget.restaurantId,
    );
    if (choice == null) return; // User dismissed — order stays pending.
    if (!mounted) return;

    setState(() => _updatingTo[orderId] = 'accepted');
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateFoodOrderStatus')
          .call({
        'orderId': orderId,
        'newStatus': 'accepted',
        'courierType': courierTypeToString(choice),
      });
    } catch (e) {
      debugPrint('_PendingOrdersSection._acceptOrder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.l10n.restaurantDashboardUpdateFailed),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingTo.remove(orderId));
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: _handleRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Header (greeting)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: widget.headerBuilder()),
          ),

          // Section label row
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  widget.sectionLabel,
                  widget.viewAllLabel,
                ],
              ),
            ),
          ),

          // Orders content
          if (_loading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _buildSkeleton()),
            )
          else if (_orders.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _buildEmpty()),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF1E1E2E)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.isDark
                            ? const Color(0xFF2D2B42)
                            : const Color(0xFFF3F4F6),
                      ),
                    ),
                    child: Column(
                      children: _orders.asMap().entries.map((e) {
                        final idx = e.key;
                        final order = e.value;
                        return Column(
                          children: [
                            _OrderCard(
                              order: order,
                              locale: widget.locale,
                              l10n: widget.l10n,
                              isDark: widget.isDark,
                              updatingTo: _updatingTo[order.id],
                              onAccept: () => _acceptOrder(order.id),
                              onReject: () =>
                                  _updateStatus(order.id, 'rejected'),
                            ),
                            if (idx < _orders.length - 1)
                              Divider(
                                height: 1,
                                color: widget.isDark
                                    ? const Color(0xFF2D2B42)
                                    : const Color(0xFFF9FAFB),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),

            // Loading more indicator
            if (_loadingMore)
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFEA580C)),
                      ),
                    ),
                  ),
                ),
              ),
          ],

          // Bottom spacing
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    final base = widget.isDark ? const Color(0xFF2A2840) : Colors.grey.shade200;
    final highlight =
        widget.isDark ? const Color(0xFF3C3A55) : Colors.grey.shade100;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark
                ? const Color(0xFF2D2B42)
                : const Color(0xFFF3F4F6),
          ),
        ),
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Column(
            children: List.generate(
                3,
                (_) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(height: 11, color: Colors.white),
                                const SizedBox(height: 6),
                                Container(
                                    height: 9, width: 100, color: Colors.white),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(height: 16, width: 48, color: Colors.white),
                        ],
                      ),
                    )),
          ),
        ),
      ),
    );
  }

  // ── Empty ─────────────────────────────────────────────────────────────────

  Widget _buildEmpty() => Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark
                ? const Color(0xFF2D2B42)
                : const Color(0xFFF3F4F6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 32,
                  color: widget.isDark
                      ? const Color(0xFF3D3B55)
                      : const Color(0xFFE5E7EB),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.l10n.restaurantDashboardPendingOrdersEmpty,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark
                        ? Colors.grey[600]
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _OrderCard
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final _PendingOrder order;
  final String locale;
  final AppLocalizations l10n;
  final bool isDark;
  final String? updatingTo;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OrderCard({
    required this.order,
    required this.locale,
    required this.l10n,
    required this.isDark,
    required this.updatingTo,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _kStatusCfg[order.status]!;
    final isUpdating = updatingTo != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cfg.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cfg.icon, color: cfg.fg, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        order.buyerName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF111827),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _timeAgo(order.createdAt, locale),
                      style: TextStyle(
                        fontSize: 10,
                        color:
                            isDark ? Colors.grey[600] : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: order.totalPrice.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  TextSpan(
                    text: ' ${order.currency}',
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          isDark ? Colors.grey[500] : const Color(0xFF9CA3AF),
                    ),
                  ),
                ]),
              ),
            ],
          ),

          // ── Items ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 8),
            child: Column(
              children: order.items
                  .map((item) => _ItemChip(item: item, isDark: isDark))
                  .toList(),
            ),
          ),

          // ── Accept / Reject ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 8),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: l10n.restaurantDashboardAccept,
                    icon: Icons.check_rounded,
                    bg: const Color(0xFF22C55E),
                    fg: Colors.white,
                    loading: isUpdating && updatingTo == 'accepted',
                    enabled: !isUpdating,
                    onTap: onAccept,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: l10n.restaurantDashboardReject,
                    icon: Icons.close_rounded,
                    bg: const Color(0xFFFEF2F2),
                    fg: const Color(0xFFDC2626),
                    loading: isUpdating && updatingTo == 'rejected',
                    enabled: !isUpdating,
                    onTap: onReject,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ItemChip
// ─────────────────────────────────────────────────────────────────────────────

class _ItemChip extends StatelessWidget {
  final _OrderItem item;
  final bool isDark;
  const _ItemChip({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252336) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.quantity}× ${item.name}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1F2937),
            ),
          ),
          if (item.extras.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.extras
                  .map((e) =>
                      '+${localizeExtra(e.name, AppLocalizations.of(context))}')
                  .join(', '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[300] : const Color(0xFF4B5563),
              ),
            ),
          ],
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.description,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (item.specialNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.specialNotes,
                style: TextStyle(
                  fontSize: 10,
                  color: const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionButton
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: loading
                ? [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    ),
                  ]
                : [
                    Icon(icon, size: 13, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
