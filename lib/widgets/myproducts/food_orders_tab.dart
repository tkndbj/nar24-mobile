import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/food_order_model.dart';
import '../../models/restaurant.dart';
import '../../providers/food_cart_provider.dart';
import '../../utils/restaurant_utils.dart';

class FoodOrdersTab extends StatefulWidget {
  final ValueChanged<bool>? onHasOrders;

  const FoodOrdersTab({Key? key, this.onHasOrders}) : super(key: key);

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

  // Track which order is currently being repeated (for loading state)
  String? _repeatingOrderId;

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
      if (mounted) {
        setState(() => _isLoadingInitial = false);
        widget.onHasOrders?.call(false);
      }
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
      widget.onHasOrders?.call(_allOrders.isNotEmpty);
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
      case FoodOrderStatus.outForDelivery:
        return Colors.blue;
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
      case FoodOrderStatus.outForDelivery:
        return Icons.delivery_dining_rounded;
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
      case FoodOrderStatus.outForDelivery:
        return l10n.foodStatusOutForDelivery;
      case FoodOrderStatus.delivered:
        return l10n.foodStatusDelivered;
      case FoodOrderStatus.completed:
        return l10n.foodStatusCompleted;
      case FoodOrderStatus.cancelled:
        return l10n.foodStatusCancelled;
    }
  }

  // ── Repeat order ─────────────────────────────────────────────────────────
  Future<void> _repeatOrder(FoodOrder order) async {
    if (_repeatingOrderId != null) return; // already in progress
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final cartProvider = context.read<FoodCartProvider>();

    setState(() => _repeatingOrderId = order.id);

    try {
      // 1. Fetch restaurant document to check open status
      final restaurantDoc =
          await _firestore.collection('restaurants').doc(order.restaurantId).get();

      if (!mounted) return;

      if (!restaurantDoc.exists) {
        _showClosedDialog(l10n);
        return;
      }

      final restaurant = Restaurant.fromMap(
        restaurantDoc.data()!,
        id: restaurantDoc.id,
      );

      // 2. Check if restaurant is open
      if (!isRestaurantOpen(restaurant)) {
        _showClosedDialog(l10n);
        return;
      }

      // 3. Build cart restaurant
      final cartRestaurant = FoodCartRestaurant(
        id: order.restaurantId,
        name: order.restaurantName,
        profileImageUrl: order.restaurantProfileImage,
      );

      // 4. Fetch food documents to get current imageUrl, category, etc.
      final foodIds = order.items.map((i) => i.foodId).toSet().toList();
      final foodDataMap = <String, Map<String, dynamic>>{};
      // Firestore whereIn supports max 10 items per query
      for (int batch = 0; batch < foodIds.length; batch += 10) {
        final chunk = foodIds.sublist(
          batch,
          batch + 10 > foodIds.length ? foodIds.length : batch + 10,
        );
        final snap = await _firestore
            .collection('foods')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          foodDataMap[doc.id] = doc.data();
        }
      }

      if (!mounted) return;

      // 5. Add each item to cart
      for (int i = 0; i < order.items.length; i++) {
        final item = order.items[i];
        final foodDoc = foodDataMap[item.foodId];
        final extras = item.extras
            .map((e) => SelectedExtra(
                  name: e.name,
                  quantity: e.quantity,
                  price: e.price,
                ))
            .toList();

        final imageUrl = (foodDoc?['imageUrl'] as String?) ?? '';
        final foodCategory = (foodDoc?['foodCategory'] as String?) ?? '';
        final foodType = (foodDoc?['foodType'] as String?) ?? '';
        final foodDescription = (foodDoc?['description'] as String?) ?? '';
        final preparationTime = (foodDoc?['preparationTime'] as num?)?.toInt();

        if (i == 0) {
          // First item — may trigger restaurant conflict
          final result = await cartProvider.addItem(
            foodId: item.foodId,
            foodName: item.name,
            foodDescription: foodDescription,
            price: item.price,
            imageUrl: imageUrl,
            foodCategory: foodCategory,
            foodType: foodType,
            preparationTime: preparationTime,
            restaurant: cartRestaurant,
            quantity: item.quantity,
            extras: extras,
          );

          if (!mounted) return;

          if (result == AddItemResult.restaurantConflict) {
            final shouldReplace = await _showReplaceCartDialog(l10n);
            if (shouldReplace != true || !mounted) return;

            final clearResult = await cartProvider.clearAndAddFromNewRestaurant(
              foodId: item.foodId,
              foodName: item.name,
              foodDescription: foodDescription,
              price: item.price,
              imageUrl: imageUrl,
              foodCategory: foodCategory,
              foodType: foodType,
              preparationTime: preparationTime,
              restaurant: cartRestaurant,
              quantity: item.quantity,
              extras: extras,
            );

            if (!mounted) return;
            if (clearResult != ClearAndAddResult.added) continue;
          } else if (result == AddItemResult.error) {
            continue;
          }
        } else {
          // Subsequent items — same restaurant, just add
          await cartProvider.addItem(
            foodId: item.foodId,
            foodName: item.name,
            foodDescription: foodDescription,
            price: item.price,
            imageUrl: imageUrl,
            foodCategory: foodCategory,
            foodType: foodType,
            preparationTime: preparationTime,
            restaurant: cartRestaurant,
            quantity: item.quantity,
            extras: extras,
          );
          if (!mounted) return;
        }
      }

      // 5. Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.orderItemsAddedToCart),
            backgroundColor: const Color(0xFF00A86B),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('FoodOrdersTab: repeat order error: $e');
    } finally {
      if (mounted) setState(() => _repeatingOrderId = null);
    }
  }

  void _showClosedDialog(AppLocalizations l10n) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.restaurantCurrentlyClosed),
        content: Text(l10n.restaurantClosedCannotRepeat),
        actions: [
          CupertinoDialogAction(
            child: Text(l10n.ok),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showReplaceCartDialog(AppLocalizations l10n) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.replaceCartItems),
        content: Text(l10n.cartHasItemsFromAnotherRestaurant),
        actions: [
          CupertinoDialogAction(
            child: Text(l10n.cancel),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: Text(l10n.replaceCart),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
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
              style: TextStyle(
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
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Search-specific empty state
    if (_currentSearchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 72, color: isDark ? Colors.grey[600] : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              l10n.noOrdersFoundForSearch,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.trySearchingWithDifferentKeywords,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // Empty orders — same placeholder as food cart
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D2B3F) : Colors.orange[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.no_food_rounded,
                size: 40,
                color: isDark ? Colors.grey[600] : Colors.orange[300],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noFoodOrders,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.foodCartBrowseMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepeatOrderButton(
      FoodOrder order, AppLocalizations l10n, bool isDark) {
    final isLoading = _repeatingOrderId == order.id;
    return GestureDetector(
      onTap: isLoading ? null : () => _repeatOrder(order),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF00A86B).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00A86B).withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Color(0xFF00A86B),
                ),
              )
            else
              const Icon(Icons.replay_rounded,
                  size: 11, color: Color(0xFF00A86B)),
            const SizedBox(width: 4),
            Text(
              l10n.repeatOrder,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00A86B),
              ),
            ),
          ],
        ),
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
                          isDark ? const Color(0xFF2D2B3F) : const Color(0xFFFFF3EC),
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
                          style: TextStyle(
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
                          style: TextStyle(
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
                              style: TextStyle(
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
                        style: TextStyle(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  _buildStatusBadge(order.status, l10n),
                  const Spacer(),
                  // Repeat order button (only for delivered/completed)
                  if (order.status == FoodOrderStatus.delivered ||
                      order.status == FoodOrderStatus.completed) ...[
                    _buildRepeatOrderButton(order, l10n, isDark),
                    const SizedBox(width: 8),
                  ],
                  // Payment indicator
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                        style: TextStyle(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2B3F) : Colors.orange[50],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.no_food_rounded,
                  size: 40,
                  color: isDark ? Colors.grey[600] : Colors.orange[300],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.noFoodOrders,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.foodCartBrowseMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        color: isDark ? const Color(0xFF1C1A29) : const Color(0xFFE5E7EB),
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
