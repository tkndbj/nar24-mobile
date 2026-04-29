// lib/screens/market/my_market_orders_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';

// ============================================================================
// ORDER MODEL (list-level — lightweight)
// ============================================================================

enum MarketOrderStatus {
  pending,
  confirmed,
  rejected,
  preparing,
  outForDelivery,
  delivered,
  completed,
  cancelled,
}

MarketOrderStatus _parseStatus(String? v) {
  switch (v) {
    case 'confirmed':
      return MarketOrderStatus.confirmed;
    case 'rejected':
      return MarketOrderStatus.rejected;
    case 'preparing':
      return MarketOrderStatus.preparing;
    case 'out_for_delivery':
      return MarketOrderStatus.outForDelivery;
    case 'delivered':
      return MarketOrderStatus.delivered;
    case 'completed':
      return MarketOrderStatus.completed;
    case 'cancelled':
      return MarketOrderStatus.cancelled;
    default:
      return MarketOrderStatus.pending;
  }
}

Color _statusColor(MarketOrderStatus s) {
  switch (s) {
    case MarketOrderStatus.pending:
      return Colors.grey;
    case MarketOrderStatus.confirmed:
      return const Color(0xFF00A86B);
    case MarketOrderStatus.rejected:
      return Colors.red;
    case MarketOrderStatus.preparing:
      return Colors.orange;
    case MarketOrderStatus.outForDelivery:
      return Colors.blue;
    case MarketOrderStatus.delivered:
    case MarketOrderStatus.completed:
      return const Color(0xFF00A86B);
    case MarketOrderStatus.cancelled:
      return Colors.red;
  }
}

IconData _statusIcon(MarketOrderStatus s) {
  switch (s) {
    case MarketOrderStatus.pending:
      return Icons.schedule;
    case MarketOrderStatus.confirmed:
      return Icons.check_circle_outline;
    case MarketOrderStatus.rejected:
      return Icons.cancel_outlined;
    case MarketOrderStatus.preparing:
      return Icons.inventory_2_outlined;
    case MarketOrderStatus.outForDelivery:
      return Icons.delivery_dining_rounded;
    case MarketOrderStatus.delivered:
    case MarketOrderStatus.completed:
      return Icons.check_circle;
    case MarketOrderStatus.cancelled:
      return Icons.cancel;
  }
}

String _statusLabel(MarketOrderStatus s, AppLocalizations l10n) {
  switch (s) {
    case MarketOrderStatus.pending:
      return l10n.marketOrderStatusPending;
    case MarketOrderStatus.confirmed:
      return l10n.marketOrderStatusConfirmed;
    case MarketOrderStatus.rejected:
      return l10n.marketOrderStatusRejected;
    case MarketOrderStatus.preparing:
      return l10n.marketOrderStatusPreparing;
    case MarketOrderStatus.outForDelivery:
      return l10n.marketOrderStatusOutForDelivery;
    case MarketOrderStatus.delivered:
      return l10n.marketOrderStatusDelivered;
    case MarketOrderStatus.completed:
      return l10n.marketOrderStatusCompleted;
    case MarketOrderStatus.cancelled:
      return l10n.marketOrderStatusCancelled;
  }
}

class _MarketOrder {
  final String id;
  final double totalPrice;
  final String currency;
  final int itemCount;
  final MarketOrderStatus status;
  final bool isPaid;
  final String paymentMethod;
  final Timestamp createdAt;
  final List<_OrderItemPreview> items;

  const _MarketOrder({
    required this.id,
    required this.totalPrice,
    required this.currency,
    required this.itemCount,
    required this.status,
    required this.isPaid,
    required this.paymentMethod,
    required this.createdAt,
    required this.items,
  });

  String itemsPreview(AppLocalizations l10n) {
    if (items.isEmpty) return l10n.marketOrderItemCount(itemCount);
    final names = items.take(3).map((i) => i.name).join(', ');
    if (items.length > 3) return '$names...';
    return names;
  }

  factory _MarketOrder.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((m) => _OrderItemPreview(
              name: (m['name'] as String?) ?? '',
              brand: (m['brand'] as String?) ?? '',
              quantity: (m['quantity'] as num?)?.toInt() ?? 1,
            ))
        .toList();

    return _MarketOrder(
      id: doc.id,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] as String?) ?? 'TL',
      itemCount: (d['itemCount'] as num?)?.toInt() ?? items.length,
      status: _parseStatus(d['status'] as String?),
      isPaid: (d['isPaid'] as bool?) ?? false,
      paymentMethod: (d['paymentMethod'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?) ?? Timestamp.now(),
      items: items,
    );
  }
}

class _OrderItemPreview {
  final String name;
  final String brand;
  final int quantity;
  const _OrderItemPreview(
      {required this.name, required this.brand, required this.quantity});
}

// ============================================================================
// SCREEN
// ============================================================================

class MyMarketOrdersScreen extends StatefulWidget {
  const MyMarketOrdersScreen({super.key});

  @override
  State<MyMarketOrdersScreen> createState() => _MyMarketOrdersScreenState();
}

class _MyMarketOrdersScreenState extends State<MyMarketOrdersScreen> {
  static const _pageSize = 20;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _scrollController = ScrollController();

  List<_MarketOrder> _orders = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      if (!_isLoadingMore && !_hasReachedEnd && _error == null) {
        _loadNextPage();
      }
    }
  }

  Future<void> _loadInitialPage() async {
    setState(() {
      _isLoadingInitial = true;
      _error = null;
      _orders = [];
      _lastDoc = null;
      _hasReachedEnd = false;
    });
    await _fetchPage(isInitial: true);
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || _hasReachedEnd || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    await _fetchPage(isInitial: false);
  }

  Future<void> _fetchPage({required bool isInitial}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingInitial = false);
      return;
    }

    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('orders-market')
          .where('buyerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snap = await q.get();
      final newOrders = snap.docs.map(_MarketOrder.fromDoc).toList();

      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _orders = newOrders;
        } else {
          _orders = [..._orders, ...newOrders];
        }
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasReachedEnd = newOrders.length < _pageSize;
        _isLoadingInitial = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('[MarketOrders] Fetch error: $e');
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.marketOrdersLoadError;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(
          l10n.myMarketOrdersTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_auth.currentUser == null) return _buildEmpty(isDark);
    if (_error != null) return _buildError(isDark);
    if (_isLoadingInitial) return _buildShimmer(isDark);
    if (_orders.isEmpty) return _buildEmpty(isDark);
    return _buildList(isDark);
  }

  Widget _buildList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadInitialPage,
      color: Colors.green,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _orders.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          if (index == _orders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(
                    color: Colors.green, strokeWidth: 3),
              ),
            );
          }
          return _OrderCard(order: _orders[index], isDark: isDark);
        },
      ),
    );
  }

  Widget _buildShimmer(bool isDark) {
    final base = isDark ? const Color(0xFF2D2B3F) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3A3850) : Colors.grey.shade100;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
              color: base, borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white70 : Colors.grey[700])),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInitialPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(l10n.marketOrdersTryAgain,
                style: const TextStyle(color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2B3F) : Colors.green[50],
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.shopping_bag_outlined,
                size: 40, color: isDark ? Colors.grey[600] : Colors.green[300]),
          ),
          const SizedBox(height: 24),
          Text(l10n.marketOrdersEmptyTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              )),
          const SizedBox(height: 6),
          Text(l10n.marketOrdersEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[500] : Colors.grey[600])),
        ]),
      ),
    );
  }
}

// ============================================================================
// ORDER CARD
// ============================================================================

class _OrderCard extends StatelessWidget {
  final _MarketOrder order;
  final bool isDark;

  const _OrderCard({required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat('dd/MM/yyyy').format(order.createdAt.toDate());
    final color = _statusColor(order.status);

    return GestureDetector(
      onTap: () => context.push('/market-order-detail/${order.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF211F31) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.grey.shade200,
              blurRadius: 6,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Main row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Market icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          isDark ? const Color(0xFF2D2B3F) : Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.shopping_bag_rounded,
                        color: Colors.green[600], size: 24),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.marketBrandName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          order.itemsPreview(l10n),
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${order.totalPrice.toStringAsFixed(2)} ${order.currency}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.green[400] : Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Date + chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.chevron_right,
                          color: Colors.green, size: 22),
                      const SizedBox(height: 6),
                      Text(dateStr,
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),

            // ── Status strip ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(
                    top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.grey.shade100)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withOpacity(0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_statusIcon(order.status), size: 11, color: color),
                      const SizedBox(width: 4),
                      Text(_statusLabel(order.status, l10n),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ]),
                  ),
                  const Spacer(),
                  // Payment indicator
                  Icon(
                    order.isPaid
                        ? Icons.credit_card_rounded
                        : Icons.payments_outlined,
                    size: 13,
                    color: order.isPaid
                        ? (isDark ? Colors.green[300] : Colors.green[700])
                        : (isDark ? Colors.amber[300] : Colors.amber[700]),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order.isPaid ? l10n.marketPaymentPaid : l10n.marketPaymentAtDoor,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: order.isPaid
                            ? (isDark ? Colors.green[300] : Colors.green[700])
                            : (isDark ? Colors.amber[300] : Colors.amber[700])),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
