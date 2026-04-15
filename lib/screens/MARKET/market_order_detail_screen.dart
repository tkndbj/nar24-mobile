// lib/screens/market/market_order_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';

// ============================================================================
// DATA MODELS (screen-local, richer than list model)
// ============================================================================

enum _Status {
  pending,
  confirmed,
  rejected,
  preparing,
  outForDelivery,
  delivered,
  completed,
  cancelled,
}

extension _StatusX on _Status {
  static _Status fromString(String? v) {
    switch (v) {
      case 'confirmed':
        return _Status.confirmed;
      case 'rejected':
        return _Status.rejected;
      case 'preparing':
        return _Status.preparing;
      case 'out_for_delivery':
        return _Status.outForDelivery;
      case 'delivered':
        return _Status.delivered;
      case 'completed':
        return _Status.completed;
      case 'cancelled':
        return _Status.cancelled;
      default:
        return _Status.pending;
    }
  }

  Color get color {
    switch (this) {
      case _Status.pending:
        return const Color(0xFFF59E0B);
      case _Status.confirmed:
        return const Color(0xFF0D9488);
      case _Status.rejected:
        return const Color(0xFFEF4444);
      case _Status.preparing:
        return const Color(0xFFF97316);
      case _Status.outForDelivery:
        return const Color(0xFF3B82F6);
      case _Status.delivered:
      case _Status.completed:
        return const Color(0xFF10B981);
      case _Status.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  IconData get icon {
    switch (this) {
      case _Status.pending:
        return Icons.schedule;
      case _Status.confirmed:
        return Icons.check_circle_outline;
      case _Status.rejected:
        return Icons.cancel_outlined;
      case _Status.preparing:
        return Icons.inventory_2_outlined;
      case _Status.outForDelivery:
        return Icons.delivery_dining_rounded;
      case _Status.delivered:
      case _Status.completed:
        return Icons.check_circle;
      case _Status.cancelled:
        return Icons.cancel;
    }
  }

  String labelFor(AppLocalizations l10n) {
    switch (this) {
      case _Status.pending:
        return l10n.marketOrderStatusPending;
      case _Status.confirmed:
        return l10n.marketOrderStatusConfirmed;
      case _Status.rejected:
        return l10n.marketOrderStatusRejected;
      case _Status.preparing:
        return l10n.marketOrderStatusPreparing;
      case _Status.outForDelivery:
        return l10n.marketOrderStatusOutForDelivery;
      case _Status.delivered:
        return l10n.marketOrderStatusDelivered;
      case _Status.completed:
        return l10n.marketOrderStatusCompleted;
      case _Status.cancelled:
        return l10n.marketOrderStatusCancelled;
    }
  }
}

class _Item {
  final String itemId;
  final String name;
  final String brand;
  final String type;
  final String category;
  final double price;
  final int quantity;
  final double? itemTotal;

  const _Item({
    required this.itemId,
    required this.name,
    required this.brand,
    required this.type,
    required this.category,
    required this.price,
    required this.quantity,
    this.itemTotal,
  });

  double get total => itemTotal ?? (price * quantity);

  factory _Item.fromMap(Map<String, dynamic> m) => _Item(
        itemId: (m['itemId'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        brand: (m['brand'] as String?) ?? '',
        type: (m['type'] as String?) ?? '',
        category: (m['category'] as String?) ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        itemTotal: (m['itemTotal'] as num?)?.toDouble(),
      );
}

class _Address {
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String? phoneNumber;

  const _Address({
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    this.phoneNumber,
  });

  factory _Address.fromMap(Map<String, dynamic> m) => _Address(
        addressLine1: (m['addressLine1'] as String?) ?? '',
        addressLine2: m['addressLine2'] as String?,
        city: (m['city'] as String?) ?? '',
        phoneNumber: m['phoneNumber'] as String?,
      );
}

class _OrderDetail {
  final String id;
  final List<_Item> items;
  final double subtotal;
  final double deliveryFee;
  final double totalPrice;
  final String currency;
  final String paymentMethod;
  final bool isPaid;
  final _Status status;
  final _Address? deliveryAddress;
  final String? orderNotes;
  final String? buyerPhone;
  final Timestamp createdAt;

  const _OrderDetail({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalPrice,
    required this.currency,
    required this.paymentMethod,
    required this.isPaid,
    required this.status,
    this.deliveryAddress,
    this.orderNotes,
    this.buyerPhone,
    required this.createdAt,
  });

  factory _OrderDetail.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'] as List<dynamic>? ?? [];
    final items =
        rawItems.whereType<Map<String, dynamic>>().map(_Item.fromMap).toList();
    final rawAddr = d['deliveryAddress'];
    final address =
        rawAddr is Map<String, dynamic> ? _Address.fromMap(rawAddr) : null;

    return _OrderDetail(
      id: doc.id,
      items: items,
      subtotal: (d['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] as String?) ?? 'TL',
      paymentMethod: (d['paymentMethod'] as String?) ?? '',
      isPaid: (d['isPaid'] as bool?) ?? false,
      status: _StatusX.fromString(d['status'] as String?),
      deliveryAddress: address,
      orderNotes: d['orderNotes'] as String?,
      buyerPhone: d['buyerPhone'] as String?,
      createdAt: (d['createdAt'] as Timestamp?) ?? Timestamp.now(),
    );
  }
}

// ============================================================================
// SCREEN
// ============================================================================

class MarketOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const MarketOrderDetailScreen({super.key, required this.orderId});

  @override
  State<MarketOrderDetailScreen> createState() =>
      _MarketOrderDetailScreenState();
}

class _MarketOrderDetailScreenState extends State<MarketOrderDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  _OrderDetail? _order;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _loadOrder();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders-market')
          .doc(widget.orderId)
          .get();
      if (!snap.exists) throw Exception('Order not found');
      setState(() {
        _order = _OrderDetail.fromDoc(snap);
        _isLoading = false;
      });
      _animCtrl.forward();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _fmt(double v) => NumberFormat('#,##0').format(v);
  String _fmtDate(Timestamp ts) =>
      DateFormat('dd/MM/yy HH:mm').format(ts.toDate());

  BoxDecoration _card(bool isDark) => BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Color _innerBg(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC);

  // ── App bar ───────────────────────────────────────────────────────────
  Widget _buildAppBar(bool isDark) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF10B981), Color(0xFF059669)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(AppLocalizations.of(context)!.marketOrderDetailTitle,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text(AppLocalizations.of(context)!.marketBrandName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.shopping_bag,
                      size: 24, color: Colors.white),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Order header ──────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    final o = _order!;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: _card(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Top row
        Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.green.withOpacity(0.1),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child:
                const Icon(Icons.receipt_long, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.marketOrderNumberLabel,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
              const SizedBox(height: 2),
              Text('#${widget.orderId.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600])),
            ],
          )),
          _statusBadge(o.status),
        ]),
        const SizedBox(height: 12),

        // Info grid
        Row(children: [
          Expanded(
              child: _infoCell(
                  isDark,
                  l10n.marketOrderDateLabel,
                  Text(_fmtDate(o.createdAt),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A1A))))),
          const SizedBox(width: 8),
          Expanded(
              child: _infoCell(
                  isDark,
                  l10n.marketOrderDeliveryLabel,
                  Row(children: [
                    Icon(Icons.location_on_outlined,
                        size: 13, color: Colors.green[600]),
                    const SizedBox(width: 4),
                    Text(l10n.marketOrderDeliveryLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[600])),
                  ]))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _infoCell(
                  isDark,
                  l10n.marketOrderPaymentMethodLabel,
                  Row(children: [
                    Icon(
                        o.paymentMethod == 'card'
                            ? Icons.credit_card_rounded
                            : Icons.payments_outlined,
                        size: 13,
                        color: o.paymentMethod == 'card'
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(o.paymentMethod == 'card' ? l10n.marketOrderPaymentCard : l10n.marketOrderPaymentAtDoor,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A))),
                  ]))),
          const SizedBox(width: 8),
          Expanded(
              child: _infoCell(
                  isDark,
                  l10n.marketOrderPaymentStatusLabel,
                  Text(o.isPaid ? l10n.marketPaymentPaid : l10n.marketOrderStatusPending,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: o.isPaid
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B))))),
        ]),
      ]),
    );
  }

  Widget _statusBadge(_Status s) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.icon, size: 10, color: s.color),
        const SizedBox(width: 4),
        Text(s.labelFor(l10n),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: s.color)),
      ]),
    );
  }

  Widget _infoCell(bool isDark, String label, Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _innerBg(isDark), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey[500] : Colors.grey[500])),
        const SizedBox(height: 2),
        child,
      ]),
    );
  }

  // ── Items ─────────────────────────────────────────────────────────────
  Widget _buildItems(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _order!.items.asMap().entries.map((e) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: e.key == _order!.items.length - 1 ? 0 : 12),
            child: _buildItemCard(e.value, isDark),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemCard(_Item item, bool isDark) {
    final cat = kMarketCategoryMap[item.category];
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: _card(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Category emoji placeholder
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: cat != null
                  ? cat.color.withOpacity(isDark ? 0.15 : 0.1)
                  : (isDark ? Colors.grey[800] : Colors.grey[100]),
              border: Border.all(
                  color: cat != null
                      ? cat.color.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2)),
            ),
            alignment: Alignment.center,
            child:
                Text(cat?.emoji ?? '📦', style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (item.brand.isNotEmpty)
                  Text(item.brand,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700])),
                Text(item.name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (item.type.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.type,
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[600])),
                  ),
              ])),
        ]),
        const SizedBox(height: 12),

        // Price grid
        Row(children: [
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_fmt(item.price)} ${_order!.currency}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green)),
              Text('${l10n.marketOrderQuantityLabel}: ${item.quantity}',
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600])),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _innerBg(isDark),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.marketOrderTotalLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey[500] : Colors.grey[500])),
              Text('${_fmt(item.total)} ${_order!.currency}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
            ]),
          )),
        ]),
      ]),
    );
  }

  // ── Delivery address ──────────────────────────────────────────────────
  Widget _buildAddress(bool isDark) {
    final addr = _order!.deliveryAddress;
    if (addr == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _card(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF10B981).withOpacity(0.1),
              border:
                  Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
            ),
            child: const Icon(Icons.location_on,
                color: Color(0xFF10B981), size: 20),
          ),
          const SizedBox(width: 12),
          Text(l10n.marketCheckoutDeliveryAddressTitle,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _innerBg(isDark), borderRadius: BorderRadius.circular(8)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                [addr.addressLine1, addr.addressLine2]
                    .where((s) => s != null && s.isNotEmpty)
                    .join(', '),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
            const SizedBox(height: 4),
            Text(addr.city,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
            if (addr.phoneNumber != null && addr.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.phone,
                      size: 12, color: Color(0xFF10B981)),
                ),
                const SizedBox(width: 8),
                Text(addr.phoneNumber!,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : const Color(0xFF1A1A1A))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Order notes ───────────────────────────────────────────────────────
  Widget _buildNotes(bool isDark) {
    final notes = _order!.orderNotes;
    if (notes == null || notes.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _card(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              border:
                  Border.all(color: const Color(0xFFF59E0B).withOpacity(0.2)),
            ),
            child: const Icon(Icons.sticky_note_2_outlined,
                color: Color(0xFFF59E0B), size: 20),
          ),
          const SizedBox(width: 12),
          Text(l10n.marketCheckoutOrderNoteTitle,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _innerBg(isDark), borderRadius: BorderRadius.circular(8)),
          child: Text(notes,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700])),
        ),
      ]),
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────
  Widget _buildSummary(bool isDark) {
    final o = _order!;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _card(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.green.withOpacity(0.1),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: const Icon(Icons.receipt, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Text(l10n.marketCartOrderSummary,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _innerBg(isDark), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            _summaryRow(
                l10n.marketOrderSubtotalLabel, '${_fmt(o.subtotal)} ${o.currency}', isDark),
            const SizedBox(height: 8),
            _summaryRow(
                l10n.marketOrderDeliveryLabel,
                o.deliveryFee == 0
                    ? l10n.marketOrderDeliveryFree
                    : '${_fmt(o.deliveryFee)} ${o.currency}',
                isDark,
                valueColor:
                    o.deliveryFee == 0 ? const Color(0xFF10B981) : null),
            const SizedBox(height: 12),
            Container(
                height: 1,
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.2)),
            const SizedBox(height: 12),
            _summaryRow(l10n.marketOrderTotalLabel, '${_fmt(o.totalPrice)} ${o.currency}', isDark,
                isTotal: true),
            const SizedBox(height: 10),
            Row(children: [
              Icon(
                  o.isPaid
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  size: 13,
                  color: o.isPaid
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                  o.isPaid
                      ? l10n.marketOrderPaidOnline
                      : l10n.marketOrderPayOnDelivery,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: o.isPaid
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _summaryRow(String label, String value, bool isDark,
      {Color? valueColor, bool isTotal = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label,
          style: isTotal
              ? TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))
              : TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600])),
      Text(value,
          style: isTotal
              ? const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.green)
              : TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: valueColor ??
                      (isDark ? Colors.white : const Color(0xFF1A1A1A)))),
    ]);
  }

  // ── Loading / Error ───────────────────────────────────────────────────
  Widget _buildLoading(bool isDark) {
    final base = isDark ? const Color(0xFF211F31) : Colors.grey[300]!;
    final highlight = isDark ? const Color(0xFF3A3850) : Colors.grey[100]!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        ...List.generate(
            4,
            (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Shimmer.fromColors(
                    baseColor: base,
                    highlightColor: highlight,
                    child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(12))),
                  ),
                )),
      ]),
    );
  }

  Widget _buildError(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: _card(isDark),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.error_outline, size: 32, color: Colors.red),
        ),
        const SizedBox(height: 16),
        Text(l10n.marketOrderLoadFailed,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
        const SizedBox(height: 6),
        Text(_error!,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600]),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _loadOrder,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(l10n.marketOrdersTryAgain),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(isDark),
          _isLoading
              ? SliverFillRemaining(child: _buildLoading(isDark))
              : _error != null
                  ? SliverFillRemaining(child: _buildError(isDark))
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: Column(children: [
                              _buildHeader(isDark),
                              const SizedBox(height: 12),
                              _buildItems(isDark),
                              if (_order!.orderNotes?.isNotEmpty == true) ...[
                                const SizedBox(height: 12),
                                _buildNotes(isDark),
                              ],
                              if (_order!.deliveryAddress != null) ...[
                                const SizedBox(height: 12),
                                _buildAddress(isDark),
                              ],
                              const SizedBox(height: 12),
                              _buildSummary(isDark),
                              const SizedBox(height: 32),
                            ]),
                          ),
                        ),
                      ]),
                    ),
        ],
      ),
    );
  }
}
