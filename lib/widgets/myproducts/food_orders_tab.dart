import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/food_order_model.dart';

class FoodOrdersTab extends StatefulWidget {
  const FoodOrdersTab({Key? key}) : super(key: key);

  @override
  State<FoodOrdersTab> createState() => FoodOrdersTabState();
}

class FoodOrdersTabState extends State<FoodOrdersTab>
    with AutomaticKeepAliveClientMixin {
  // ── Config ──────────────────────────────────────────────────────────────────
  static const int _pageSize = 20;
  static const Duration _scrollThrottleDelay = Duration(milliseconds: 100);

  @override
  bool get wantKeepAlive => true;

  // ── Firebase ─────────────────────────────────────────────────────────────
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // ── State ─────────────────────────────────────────────────────────────────
  final _scrollController = ScrollController();
  Timer? _scrollThrottle;

  List<FoodOrder> _allOrders = [];
  List<FoodOrder> _filteredOrders = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;
  String? _errorMessage;

  String _currentSearchQuery = '';

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialPage();
  }

  @override
  void dispose() {
    _scrollThrottle?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Public API (called by parent screen for search) ───────────────────────
  void applySearch(String query) {
    if (!mounted) return;
    final q = query.trim().toLowerCase();
    setState(() {
      _currentSearchQuery = q;
      _filteredOrders = _filterOrders(_allOrders, q);
    });
  }

  // ── Scroll ────────────────────────────────────────────────────────────────
  void _onScroll() {
    if (_scrollThrottle?.isActive ?? false) return;
    _scrollThrottle = Timer(_scrollThrottleDelay, () {
      if (!mounted) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent * 0.85) {
        if (!_isLoadingMore && !_hasReachedEnd && _errorMessage == null) {
          _loadNextPage();
        }
      }
    });
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadInitialPage() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
      _errorMessage = null;
      _allOrders = [];
      _filteredOrders = [];
      _lastDoc = null;
      _hasReachedEnd = false;
    });
    await _fetchPage(isInitial: true);
  }

  Future<void> _loadNextPage() async {
    if (!mounted || _isLoadingMore || _hasReachedEnd || _lastDoc == null)
      return;
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
          .collection('orders-food')
          .where('buyerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snapshot = await q.get();
      final newOrders = snapshot.docs.map(FoodOrder.fromDoc).toList();

      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _allOrders = newOrders;
        } else {
          _allOrders = [..._allOrders, ...newOrders];
        }
        _filteredOrders = _filterOrders(_allOrders, _currentSearchQuery);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasReachedEnd = newOrders.length < _pageSize;
        _isLoadingInitial = false;
        _isLoadingMore = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('FoodOrdersTab: error fetching orders: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    }
  }

  List<FoodOrder> _filterOrders(List<FoodOrder> orders, String query) {
    if (query.isEmpty) return orders;
    return orders.where((o) {
      final matchRestaurant = o.restaurantName.toLowerCase().contains(query);
      final matchItem =
          o.items.any((i) => i.name.toLowerCase().contains(query));
      return matchRestaurant || matchItem;
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() => _currentSearchQuery = '');
    await _loadInitialPage();
  }

  // ── Status helpers ────────────────────────────────────────────────────────
  Color _statusColor(FoodOrderStatus status) {
    switch (status) {
      case FoodOrderStatus.pending:
        return Colors.grey;
      case FoodOrderStatus.accepted:
        return const Color(0xFF00A86B); // teal/jade
      case FoodOrderStatus.rejected:
        return Colors.red;
      case FoodOrderStatus.preparing:
        return Colors.orange;
      case FoodOrderStatus.ready:
        return Colors.indigo;
      case FoodOrderStatus.delivered:
      case FoodOrderStatus.completed:
        return const Color(0xFF00A86B);
      case FoodOrderStatus.cancelled:
        return Colors.red;
    }
  }

  IconData _statusIcon(FoodOrderStatus status) {
    switch (status) {
      case FoodOrderStatus.pending:
        return Icons.schedule;
      case FoodOrderStatus.accepted:
        return Icons.check_circle_outline;
      case FoodOrderStatus.rejected:
        return Icons.cancel_outlined;
      case FoodOrderStatus.preparing:
        return Icons.restaurant;
      case FoodOrderStatus.ready:
        return Icons.shopping_bag_outlined;
      case FoodOrderStatus.delivered:
      case FoodOrderStatus.completed:
        return Icons.check_circle;
      case FoodOrderStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _statusLabel(FoodOrderStatus status, AppLocalizations l10n) {
    switch (status) {
      case FoodOrderStatus.pending:
        return l10n.foodStatusPending;
      case FoodOrderStatus.accepted:
        return l10n.foodStatusAccepted;
      case FoodOrderStatus.rejected:
        return l10n.foodStatusRejected;
      case FoodOrderStatus.preparing:
        return l10n.foodStatusPreparing;
      case FoodOrderStatus.ready:
        return l10n.foodStatusReady;
      case FoodOrderStatus.delivered:
        return l10n.foodStatusDelivered;
      case FoodOrderStatus.completed:
        return l10n.foodStatusCompleted;
      case FoodOrderStatus.cancelled:
        return l10n.foodStatusCancelled;
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlight =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;
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
            color: base,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 56,
                color: isDark ? Colors.red.shade300 : Colors.red.shade600),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text('Retry',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_menu_rounded,
              size: 72, color: isDark ? Colors.grey[600] : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _currentSearchQuery.isNotEmpty
                ? l10n.noOrdersFoundForSearch
                : l10n.noFoodOrders,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          if (_currentSearchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.trySearchingWithDifferentKeywords,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(FoodOrderStatus status, AppLocalizations l10n) {
    final color = _statusColor(status);
    final icon = _statusIcon(status);
    final label = _statusLabel(status, l10n);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(FoodOrder order, AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('dd/MM/yyyy').format(order.createdAt.toDate());

    return GestureDetector(
      onTap: () => context.push('/food-order-detail/${order.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
            // ── Main row ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Restaurant image / icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          isDark ? Colors.grey[800] : const Color(0xFFFFF3EC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (order.restaurantProfileImage?.isNotEmpty == true)
                        ? Image.network(
                            order.restaurantProfileImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.restaurant,
                                color: Colors.orange,
                                size: 24),
                          )
                        : const Icon(Icons.restaurant,
                            color: Colors.orange, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Info column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.restaurantName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          order.itemsPreview,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              '${order.totalPrice.toStringAsFixed(0)} ${order.currency}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.orangeAccent
                                    : Colors.deepOrange,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: isDark
                                  ? Colors.green[300]
                                  : Colors.green[700],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Right: date + chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(Icons.chevron_right,
                          color: const Color(0xFF00A86B), size: 22),
                      const SizedBox(height: 6),
                      Text(
                        dateStr,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Status strip ──────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade100,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusBadge(order.status, l10n),
                  // Payment indicator
                  Row(
                    children: [
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
                        order.isPaid ? l10n.paid : l10n.payAtDoor,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: order.isPaid
                              ? (isDark ? Colors.green[300] : Colors.green[700])
                              : (isDark
                                  ? Colors.amber[300]
                                  : Colors.amber[700]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF00A86B),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredOrders.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          if (index == _filteredOrders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00A86B),
                  strokeWidth: 3,
                ),
              ),
            );
          }
          return _buildOrderCard(_filteredOrders[index], l10n);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_auth.currentUser == null) {
      return Center(
        child: Text(
          'Please log in to see your food orders.',
          style: GoogleFonts.inter(
              color: isDark ? Colors.white70 : Colors.grey[700]),
        ),
      );
    }

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1A29) : null,
          gradient: isDark
              ? null
              : LinearGradient(
                  colors: [Colors.grey[100]!, Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: Builder(builder: (_) {
          if (_errorMessage != null) return _buildError();
          if (_isLoadingInitial) return _buildShimmer();
          if (_filteredOrders.isEmpty) return _buildEmpty(l10n);
          return _buildList(l10n);
        }),
      ),
    );
  }
}
