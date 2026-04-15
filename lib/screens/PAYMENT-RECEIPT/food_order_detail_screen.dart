import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../utils/food_localization.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS (screen-local, richer than the list model)
// ═══════════════════════════════════════════════════════════════════════════

enum _FoodOrderStatus {
  pending,
  accepted,
  rejected,
  confirmed,
  preparing,
  ready,
  outForDelivery,
  delivered,
  completed,
  cancelled,
}

extension _FoodOrderStatusX on _FoodOrderStatus {
  static _FoodOrderStatus fromString(String? v) {
    switch (v) {
      case 'accepted':
        return _FoodOrderStatus.accepted;
      case 'rejected':
        return _FoodOrderStatus.rejected;
      case 'confirmed':
        return _FoodOrderStatus.confirmed;
      case 'preparing':
        return _FoodOrderStatus.preparing;
      case 'ready':
        return _FoodOrderStatus.ready;
      case 'out_for_delivery':
      case 'outForDelivery':
        return _FoodOrderStatus.outForDelivery;
      case 'delivered':
        return _FoodOrderStatus.delivered;
      case 'completed':
        return _FoodOrderStatus.completed;
      case 'cancelled':
        return _FoodOrderStatus.cancelled;
      case 'pending':
      default:
        return _FoodOrderStatus.pending;
    }
  }

  Color get color {
    switch (this) {
      case _FoodOrderStatus.pending:
        return const Color(0xFFF59E0B);
      case _FoodOrderStatus.accepted:
        return const Color(0xFF0D9488);
      case _FoodOrderStatus.rejected:
        return const Color(0xFFEF4444);
      case _FoodOrderStatus.confirmed:
        return const Color(0xFF3B82F6);
      case _FoodOrderStatus.preparing:
        return const Color(0xFFF97316);
      case _FoodOrderStatus.ready:
        return const Color(0xFF6366F1);
      case _FoodOrderStatus.outForDelivery:
        return const Color(0xFF3B82F6);
      case _FoodOrderStatus.delivered:
      case _FoodOrderStatus.completed:
        return const Color(0xFF10B981);
      case _FoodOrderStatus.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  IconData get icon {
    switch (this) {
      case _FoodOrderStatus.pending:
        return Icons.schedule;
      case _FoodOrderStatus.accepted:
        return Icons.check_circle_outline;
      case _FoodOrderStatus.rejected:
        return Icons.cancel_outlined;
      case _FoodOrderStatus.confirmed:
        return Icons.verified_outlined;
      case _FoodOrderStatus.preparing:
        return Icons.restaurant;
      case _FoodOrderStatus.ready:
        return Icons.shopping_bag_outlined;
      case _FoodOrderStatus.outForDelivery:
        return Icons.delivery_dining_rounded;
      case _FoodOrderStatus.delivered:
      case _FoodOrderStatus.completed:
        return Icons.check_circle;
      case _FoodOrderStatus.cancelled:
        return Icons.cancel;
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case _FoodOrderStatus.pending:
        return l10n.foodStatusPending;
      case _FoodOrderStatus.accepted:
        return l10n.foodStatusAccepted;
      case _FoodOrderStatus.rejected:
        return l10n.foodStatusRejected;
      case _FoodOrderStatus.confirmed:
        return l10n.foodStatusAccepted; // reuse accepted label for confirmed
      case _FoodOrderStatus.preparing:
        return l10n.foodStatusPreparing;
      case _FoodOrderStatus.ready:
        return l10n.foodStatusReady;
      case _FoodOrderStatus.outForDelivery:
        return l10n.foodStatusOutForDelivery;
      case _FoodOrderStatus.delivered:
        return l10n.foodStatusDelivered;
      case _FoodOrderStatus.completed:
        return l10n.foodStatusCompleted;
      case _FoodOrderStatus.cancelled:
        return l10n.foodStatusCancelled;
    }
  }
}

class _FoodExtra {
  final String name;
  final double price;
  final int quantity;
  const _FoodExtra(
      {required this.name, required this.price, required this.quantity});
  factory _FoodExtra.fromMap(Map<String, dynamic> m) => _FoodExtra(
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      );
}

class _FoodItem {
  final String foodId;
  final String name;
  final double price;
  final int quantity;
  final List<_FoodExtra> extras;
  final String? specialNotes;
  final double? itemTotal;

  const _FoodItem({
    required this.foodId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.extras,
    this.specialNotes,
    this.itemTotal,
  });

  factory _FoodItem.fromMap(Map<String, dynamic> m) {
    final rawExtras = m['extras'];
    final extras = rawExtras is List
        ? rawExtras
            .whereType<Map<String, dynamic>>()
            .map(_FoodExtra.fromMap)
            .toList()
        : <_FoodExtra>[];
    return _FoodItem(
      foodId: m['foodId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      price: (m['price'] as num?)?.toDouble() ?? 0,
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      extras: extras,
      specialNotes: m['specialNotes'] as String?,
      itemTotal: (m['itemTotal'] as num?)?.toDouble(),
    );
  }

  double get effectiveUnitPrice {
    final extrasTotal =
        extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    return price + extrasTotal;
  }

  double get total => itemTotal ?? (effectiveUnitPrice * quantity);
}

class _DeliveryAddress {
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String? phoneNumber;

  const _DeliveryAddress({
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    this.phoneNumber,
  });

  factory _DeliveryAddress.fromMap(Map<String, dynamic> m) => _DeliveryAddress(
        addressLine1: m['addressLine1'] as String? ?? '',
        addressLine2: m['addressLine2'] as String?,
        city: m['city'] as String? ?? '',
        phoneNumber: m['phoneNumber'] as String?,
      );
}

class _FoodOrderDetail {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final List<_FoodItem> items;
  final double subtotal;
  final double deliveryFee;
  final double totalPrice;
  final String currency;
  final String paymentMethod;
  final bool isPaid;
  final String deliveryType;
  final _FoodOrderStatus status;
  final _DeliveryAddress? deliveryAddress;
  final int? estimatedPrepTime;
  final String? orderNotes;
  final String? restaurantPhone;
  final String? buyerPhone;
  final Timestamp createdAt;

  bool get isPickup => deliveryType == 'pickup';

  const _FoodOrderDetail({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalPrice,
    required this.currency,
    required this.paymentMethod,
    required this.isPaid,
    required this.deliveryType,
    required this.status,
    this.deliveryAddress,
    this.estimatedPrepTime,
    this.orderNotes,
    this.restaurantPhone,
    this.buyerPhone,
    required this.createdAt,
  });

  factory _FoodOrderDetail.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(_FoodItem.fromMap)
            .toList()
        : <_FoodItem>[];

    final rawAddr = d['deliveryAddress'];
    final address = rawAddr is Map<String, dynamic>
        ? _DeliveryAddress.fromMap(rawAddr)
        : null;

    return _FoodOrderDetail(
      id: doc.id,
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      items: items,
      subtotal: (d['subtotal'] as num?)?.toDouble() ??
          (d['totalPrice'] as num?)?.toDouble() ??
          0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'TL',
      paymentMethod: d['paymentMethod'] as String? ?? '',
      isPaid: d['isPaid'] as bool? ?? false,
      deliveryType: d['deliveryType'] as String? ?? 'delivery',
      status: _FoodOrderStatusX.fromString(d['status'] as String?),
      deliveryAddress: address,
      estimatedPrepTime: (d['estimatedPrepTime'] as num?)?.toInt(),
      orderNotes: d['orderNotes'] as String?,
      restaurantPhone: d['restaurantPhone'] as String?,
      buyerPhone: d['buyerPhone'] as String?,
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class FoodOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const FoodOrderDetailScreen({Key? key, required this.orderId})
      : super(key: key);

  @override
  State<FoodOrderDetailScreen> createState() => _FoodOrderDetailScreenState();
}

class _FoodOrderDetailScreenState extends State<FoodOrderDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  _FoodOrderDetail? _order;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _loadOrder();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders-food')
          .doc(widget.orderId)
          .get();
      if (!snap.exists) throw Exception('Order not found');
      setState(() {
        _order = _FoodOrderDetail.fromDoc(snap);
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String _formatCurrency(double amount) => NumberFormat('#,##0').format(amount);

  String _formatDate(Timestamp ts) =>
      DateFormat('dd/MM/yy HH:mm').format(ts.toDate());

  // ═════════════════════════════════════════════════════════════════════════
  // SHARED CARD DECORATION  (identical to ShipmentStatusScreen)
  // ═════════════════════════════════════════════════════════════════════════

  BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.grey.withOpacity(0.1),
        ),
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

  // ═════════════════════════════════════════════════════════════════════════
  // APP BAR  (orange gradient — mirrors web app header)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSliverAppBar(AppLocalizations l10n, bool isDark) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      snap: false,
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
              colors: [Color(0xFFF97316), Color(0xFFEF4444)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          l10n.foodOrderDetails,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (_order != null)
                          Text(
                            _order!.restaurantName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.restaurant_menu,
                        size: 24, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LOADING SHIMMER  (same pattern as ShipmentStatusScreen)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildShimmerCard(bool isDark, {required double height}) {
    return Shimmer.fromColors(
      baseColor:
          isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[300]!,
      highlightColor:
          isDark ? const Color.fromARGB(255, 52, 48, 75) : Colors.grey[100]!,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildShimmerCard(isDark, height: 140),
          const SizedBox(height: 12),
          _buildShimmerCard(isDark, height: 160),
          const SizedBox(height: 12),
          _buildShimmerCard(isDark, height: 160),
          const SizedBox(height: 12),
          _buildShimmerCard(isDark, height: 100),
          const SizedBox(height: 12),
          _buildShimmerCard(isDark, height: 120),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ERROR STATE  (same pattern as ShipmentStatusScreen)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildErrorState(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.error_outline,
                size: 32, color: Color(0xFFEF4444)),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.failedToLoadOrder,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadOrder,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l10n.retry),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STATUS BADGE
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildStatusBadge(_FoodOrderStatus status, AppLocalizations l10n) {
    final color = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            status.label(l10n),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ORDER HEADER CARD
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildOrderHeader(AppLocalizations l10n, bool isDark) {
    final o = _order!;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Top row: icon + order ID + status badge ───────────────
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFF97316).withOpacity(0.1),
                    border: Border.all(
                        color: const Color(0xFFF97316).withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.receipt_long,
                      color: Color(0xFFF97316), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.orderNumber,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${widget.orderId.substring(0, 8).toUpperCase()}',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(o.status, l10n),
              ],
            ),
            const SizedBox(height: 12),

            // ── Info grid: date / delivery type / payment / paid status ─
            Row(
              children: [
                Expanded(
                    child: _buildInfoCell(
                  isDark: isDark,
                  label: l10n.orderDate,
                  child: Text(
                    _formatDate(o.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildInfoCell(
                  isDark: isDark,
                  label: l10n.deliveryType,
                  child: Row(
                    children: [
                      Icon(
                        o.isPickup
                            ? Icons.shopping_bag_outlined
                            : Icons.location_on_outlined,
                        size: 13,
                        color:
                            o.isPickup ? Colors.blue[600] : Colors.green[600],
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          o.isPickup ? l10n.pickup : l10n.delivery,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: o.isPickup
                                ? Colors.blue[600]
                                : Colors.green[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _buildInfoCell(
                  isDark: isDark,
                  label: l10n.paymentMethod,
                  child: Row(
                    children: [
                      Icon(
                        o.paymentMethod == 'card'
                            ? Icons.credit_card_rounded
                            : Icons.payments_outlined,
                        size: 13,
                        color: o.paymentMethod == 'card'
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          o.paymentMethod == 'card'
                              ? l10n.card
                              : l10n.payAtDoor,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white : const Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildInfoCell(
                  isDark: isDark,
                  label: l10n.paymentStatus,
                  child: Text(
                    o.isPaid ? l10n.paid : l10n.pending,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: o.isPaid
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                )),
              ],
            ),

            // ── Optional: prep time + restaurant phone ────────────────
            if (o.estimatedPrepTime != null || o.restaurantPhone != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (o.estimatedPrepTime != null)
                    Expanded(
                        child: _buildInfoCell(
                      isDark: isDark,
                      label: l10n.prepTime,
                      child: Text(
                        '${o.estimatedPrepTime} ${l10n.minutes}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                      ),
                    )),
                  if (o.estimatedPrepTime != null && o.restaurantPhone != null)
                    const SizedBox(width: 8),
                  if (o.restaurantPhone != null)
                    Expanded(
                        child: _buildInfoCell(
                      isDark: isDark,
                      label: l10n.restaurantPhone,
                      child: Row(
                        children: [
                          const Icon(Icons.phone,
                              size: 13, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              o.restaurantPhone!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Reusable info cell (matches the grid cells in ShipmentStatusScreen)
  Widget _buildInfoCell({
    required bool isDark,
    required String label,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _innerBg(isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.grey[500] : Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ORDER ITEMS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildOrderItems(AppLocalizations l10n, bool isDark) {
    if (_order!.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _order!.items.asMap().entries.map((e) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: e.key == _order!.items.length - 1 ? 0 : 12),
            child: _buildItemCard(e.value, l10n, isDark),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildItemCard(_FoodItem item, AppLocalizations l10n, bool isDark) {
    return Container(
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Item header ───────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark ? Colors.grey[800] : const Color(0xFFFFF3EC),
                    border: Border.all(
                      color:
                          isDark ? Colors.grey[700]! : const Color(0xFFFFE0C8),
                    ),
                  ),
                  child: Icon(
                    Icons.restaurant,
                    size: 20,
                    color: isDark ? Colors.grey[400] : const Color(0xFFF97316),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _order!.restaurantName,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF97316),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Price + Qty / Total grid ───────────────────────────────
            Row(
              children: [
                // Unit price + qty
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatCurrency(item.effectiveUnitPrice)} ${_order!.currency}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        Text(
                          '${l10n.qty}: ${item.quantity}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Total
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _innerBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.total,
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[500]),
                        ),
                        Text(
                          '${_formatCurrency(item.total)} ${_order!.currency}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white : const Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Extras ────────────────────────────────────────────────
            if (item.extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.grey.shade100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.extras,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.extras.map((ext) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFF97316).withOpacity(0.2),
                            ),
                          ),
                          child: Text(
                            [
                              localizeExtra(ext.name, l10n),
                              if (ext.quantity > 1) '×${ext.quantity}',
                              if (ext.price > 0)
                                '+${_formatCurrency(ext.price)} ${_order!.currency}',
                            ].join(' '),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF97316),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            // ── Special notes ─────────────────────────────────────────
            if (item.specialNotes != null && item.specialNotes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.sticky_note_2_outlined,
                        size: 14,
                        color: isDark
                            ? Colors.grey[400]
                            : const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.specialNotes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ORDER NOTES CARD
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildOrderNotes(AppLocalizations l10n, bool isDark) {
    final notes = _order!.orderNotes;
    if (notes == null || notes.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.sticky_note_2_outlined,
                      color: Color(0xFFF59E0B), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.orderNotes,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _innerBg(isDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                notes,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DELIVERY ADDRESS CARD
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildDeliveryAddress(AppLocalizations l10n, bool isDark) {
    final o = _order!;
    if (o.isPickup || o.deliveryAddress == null) return const SizedBox.shrink();
    final addr = o.deliveryAddress!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.location_on,
                      color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.deliveryAddress,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _innerBg(isDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [addr.addressLine1, addr.addressLine2]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(', '),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addr.city,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (addr.phoneNumber != null &&
                      addr.phoneNumber!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
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
                        Text(
                          addr.phoneNumber!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isDark ? Colors.white : const Color(0xFF1A1A1A),
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
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ORDER SUMMARY CARD  (same _buildSummaryRow pattern as ShipmentStatusScreen)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryRow(
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                )
              : TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
        ),
        Text(
          value,
          style: isTotal
              ? const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF97316),
                )
              : TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: valueColor ??
                      (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                ),
        ),
      ],
    );
  }

  Widget _buildOrderSummary(AppLocalizations l10n, bool isDark) {
    final o = _order!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFF97316).withOpacity(0.1),
                    border: Border.all(
                        color: const Color(0xFFF97316).withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.receipt,
                      color: Color(0xFFF97316), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.orderSummary,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _innerBg(isDark),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Subtotal
                  _buildSummaryRow(
                    l10n.subtotal,
                    '${_formatCurrency(o.subtotal)} ${o.currency}',
                    isDark,
                  ),

                  // Delivery fee (only for delivery orders)
                  if (!o.isPickup) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      l10n.deliveryFee,
                      o.deliveryFee == 0
                          ? l10n.free
                          : '${_formatCurrency(o.deliveryFee)} ${o.currency}',
                      isDark,
                      valueColor:
                          o.deliveryFee == 0 ? const Color(0xFF10B981) : null,
                    ),
                  ],

                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.2),
                  ),
                  const SizedBox(height: 12),

                  // Total
                  _buildSummaryRow(
                    l10n.total,
                    '${_formatCurrency(o.totalPrice)} ${o.currency}',
                    isDark,
                    isTotal: true,
                  ),

                  const SizedBox(height: 10),

                  // Payment note
                  Row(
                    children: [
                      Icon(
                        o.isPaid
                            ? Icons.check_circle_outline
                            : Icons.payments_outlined,
                        size: 13,
                        color: o.isPaid
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          o.isPaid ? l10n.paidOnlineNote : l10n.payAtDoorNote,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: o.isPaid
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
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

  // ═════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(l10n, isDark),
          _isLoading
              ? SliverFillRemaining(child: _buildLoadingState(isDark))
              : _error != null
                  ? SliverFillRemaining(child: _buildErrorState(l10n, isDark))
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: Column(
                              children: [
                                _buildOrderHeader(l10n, isDark),
                                const SizedBox(height: 12),
                                _buildOrderItems(l10n, isDark),
                                if (_order!.orderNotes?.isNotEmpty == true) ...[
                                  const SizedBox(height: 12),
                                  _buildOrderNotes(l10n, isDark),
                                ],
                                if (!_order!.isPickup &&
                                    _order!.deliveryAddress != null) ...[
                                  const SizedBox(height: 12),
                                  _buildDeliveryAddress(l10n, isDark),
                                ],
                                const SizedBox(height: 12),
                                _buildOrderSummary(l10n, isDark),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
        ],
      ),
    );
  }
}
