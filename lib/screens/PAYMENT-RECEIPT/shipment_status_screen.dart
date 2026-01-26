import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:shimmer/shimmer.dart';
import '../../utils/attribute_localization_utils.dart';

class ShipmentStatusScreen extends StatefulWidget {
  final String orderId;

  const ShipmentStatusScreen({
    Key? key,
    required this.orderId,
  }) : super(key: key);

  @override
  State<ShipmentStatusScreen> createState() => _ShipmentStatusScreenState();
}

class _ShipmentStatusScreenState extends State<ShipmentStatusScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _orderData;
  List<Map<String, dynamic>> _orderItems = [];
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
    _loadOrderDetails();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadOrderDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .get();

      if (!orderDoc.exists) {
        throw Exception('Order not found');
      }

      final itemsQuery = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .collection('items')
          .orderBy('timestamp', descending: false)
          .get();

      setState(() {
        _orderData = orderDoc.data();
        _orderItems = itemsQuery.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();
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

  String _formatCurrency(double amount) {
    return NumberFormat('#,##0').format(amount);
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return AppLocalizations.of(context).unknown;
    return DateFormat('dd/MM/yy').format(timestamp.toDate());
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B); // Amber
      case 'collecting':
        return Colors.orange;
      case 'in_transit':
        return const Color(0xFF3B82F6); // Blue
      case 'at_warehouse':
        return Colors.purple;
      case 'out_for_delivery':
        return Colors.indigo;
      case 'shipped':
        return const Color(0xFF3B82F6); // Blue
      case 'delivered':
        return const Color(0xFF10B981); // Green
      case 'cancelled':
      case 'failed':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6B7280); // Grey
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.schedule;
      case 'collecting':
        return Icons.person_pin_circle;
      case 'in_transit':
        return Icons.local_shipping;
      case 'at_warehouse':
        return Icons.warehouse;
      case 'out_for_delivery':
        return Icons.delivery_dining;
      case 'shipped':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.check_circle;
      case 'cancelled':
      case 'failed':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  Widget _buildStatusBadge(String status) {
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final l10n = AppLocalizations.of(context);

    String localizedStatus;
    switch (status.toLowerCase()) {
      case 'pending':
        localizedStatus = l10n.shipmentPending;
        break;
      case 'collecting':
        localizedStatus = l10n.shipmentCollecting;
        break;
      case 'in_transit':
        localizedStatus = l10n.shipmentInTransit;
        break;
      case 'at_warehouse':
        localizedStatus = l10n.shipmentAtWarehouse;
        break;
      case 'out_for_delivery':
        localizedStatus = l10n.shipmentOutForDelivery;
        break;
      case 'shipped':
        localizedStatus = l10n.shipped;
        break;
      case 'delivered':
        localizedStatus = l10n.shipmentDelivered;
        break;
      case 'cancelled':
        localizedStatus = l10n.cancelled;
        break;
      case 'failed':
        localizedStatus = l10n.shipmentFailed;
        break;
      default:
        localizedStatus = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 10,
            color: statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            localizedStatus,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSliverAppBar(
      BuildContext context, AppLocalizations l10n, bool isDark) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      snap: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
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
                          l10n.orderDetails,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (_orderData != null)
                          Text(
                            '#${widget.orderId.substring(0, 8).toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      size: 24,
                      color: Colors.white,
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

  Widget _buildLoadingState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Order Header Shimmer
          _buildShimmerCard(isDark, height: 120),
          const SizedBox(height: 12),

          // Order Items Shimmer (2 items)
          _buildShimmerCard(isDark, height: 140),
          const SizedBox(height: 12),
          _buildShimmerCard(isDark, height: 140),
          const SizedBox(height: 12),

          // Address Shimmer
          _buildShimmerCard(isDark, height: 100),
          const SizedBox(height: 12),

          // Summary Shimmer
          _buildShimmerCard(isDark, height: 120),
        ],
      ),
    );
  }

  Widget _buildShimmerCard(bool isDark, {required double height}) {
    return Shimmer.fromColors(
      baseColor: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.grey[300]!,
      highlightColor:
          isDark ? Color.fromARGB(255, 52, 48, 75) : Colors.grey[100]!,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

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
            child: const Icon(
              Icons.error_outline,
              size: 32,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.failedToLoadOrder ?? 'Failed to load order',
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
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadOrderDetails,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l10n.retry),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Determines the overall order status from order data and items
  String _getOrderStatus() {
    if (_orderData == null) return 'pending';

    // Check order-level delivery status first
    final deliveryStatus = _orderData!['deliveryStatus'] as String?;
    final distributionStatus = _orderData!['distributionStatus'] as String?;

    if (deliveryStatus == 'delivered' || distributionStatus == 'delivered') {
      return 'delivered';
    }

    // If no items, check order-level status
    if (_orderItems.isEmpty) {
      return 'pending';
    }

    // Check if all items are delivered
    final allDelivered = _orderItems.every((item) {
      final gatheringStatus = item['gatheringStatus'] as String?;
      final itemDeliveryStatus = item['deliveryStatus'] as String?;
      final deliveredInPartial = item['deliveredInPartial'] as bool? ?? false;
      return gatheringStatus == 'delivered' ||
          itemDeliveryStatus == 'delivered' ||
          deliveredInPartial;
    });

    if (allDelivered) {
      return 'delivered';
    }

    // Check if any item failed
    final anyFailed = _orderItems.any((item) {
      final gatheringStatus = item['gatheringStatus'] as String?;
      return gatheringStatus == 'failed';
    });

    if (anyFailed) {
      return 'failed';
    }

    // Determine the "lowest" status across all items
    // Priority: pending < collecting < in_transit < at_warehouse < out_for_delivery
    final statusPriority = {
      'pending': 0,
      'collecting': 1,
      'assigned': 1,
      'in_transit': 2,
      'gathered': 2,
      'at_warehouse': 3,
      'out_for_delivery': 4,
    };

    String lowestStatus = 'out_for_delivery';
    int lowestPriority = 4;

    for (final item in _orderItems) {
      final itemStatus = _getShipmentStatusFromItem(item);
      final priority = statusPriority[itemStatus] ?? 0;
      if (priority < lowestPriority) {
        lowestPriority = priority;
        lowestStatus = itemStatus;
      }
    }

    return lowestStatus;
  }

  Widget _buildOrderHeader(bool isDark) {
    if (_orderData == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final currentStatus = _getOrderStatus();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Row
            Row(
              children: [
                // Order Icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Order Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.orderNumber ?? 'Order Number',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${widget.orderId.substring(0, 8).toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status
                _buildStatusBadge(currentStatus),
              ],
            ),

            const SizedBox(height: 12),

            // Details Row
            Row(
              children: [
                // Order Date
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderDate ?? 'Order Date',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                          ),
                        ),
                        Text(
                          _formatDate(_orderData!['timestamp']),
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
                const SizedBox(width: 8),
                // Payment Method
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.paymentMethod ?? 'Payment Method',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                          ),
                        ),
                        Text(
                          _orderData!['paymentMethod'] ?? l10n.unknown,
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
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItems(bool isDark) {
    if (_orderItems.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _orderItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Padding(
            padding: EdgeInsets.only(
                bottom: index == _orderItems.length - 1 ? 0 : 12),
            child: _buildCompactOrderItemCard(context, item, l10n, isDark),
          );
        }).toList(),
      ),
    );
  }

  /// Determines the shipment status from item data
  String _getShipmentStatusFromItem(Map<String, dynamic> item) {
    final gatheringStatus = item['gatheringStatus'] as String?;
    final deliveryStatus = item['deliveryStatus'] as String?;
    final deliveredInPartial = item['deliveredInPartial'] as bool? ?? false;

    // Check if delivered
    if (gatheringStatus == 'delivered' ||
        deliveryStatus == 'delivered' ||
        deliveredInPartial) {
      return 'delivered';
    }

    // Check for failures
    if (gatheringStatus == 'failed') {
      return 'failed';
    }

    // Check gathering status progression
    switch (gatheringStatus) {
      case 'at_warehouse':
        return 'at_warehouse';
      case 'gathered':
        return 'in_transit';
      case 'assigned':
        return 'collecting';
      case 'pending':
      default:
        return 'pending';
    }
  }

// Replace the _buildCompactOrderItemCard method with this updated version:
  Widget _buildCompactOrderItemCard(BuildContext context,
      Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    final productName = item['productName'] ?? l10n.unknownProduct;
    final productImage = item['productImage'] ?? '';
    final price = (item['price'] ?? 0).toDouble();
    final quantity = item['quantity'] ?? 1;
    final currency = item['currency'] ?? 'TL';
    final sellerName = item['sellerName'] ?? l10n.unknown;
    final shipmentStatus = _getShipmentStatusFromItem(item);

    final selectedAttributes =
        item['selectedAttributes'] as Map<String, dynamic>? ?? {};

    final totalAmount = price * quantity;

    return Container(
      decoration: BoxDecoration(
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
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Row
            Row(
              children: [
                // Product Image
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: isDark ? Colors.grey[800] : Colors.grey[50],
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                    ),
                  ),
                  child: productImage.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: productImage,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Icon(
                              Icons.image_rounded,
                              color:
                                  isDark ? Colors.grey[600] : Colors.grey[400],
                              size: 20,
                            ),
                            errorWidget: (context, error, stackTrace) {
                              return Icon(
                                Icons.image_not_supported_outlined,
                                color: isDark
                                    ? Colors.grey[600]
                                    : Colors.grey[400],
                                size: 20,
                              );
                            },
                          ),
                        )
                      : Icon(
                          Icons.inventory_2_outlined,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${l10n.soldBy ?? 'Sold by'} $sellerName',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status
                _buildStatusBadge(shipmentStatus),
              ],
            ),

            const SizedBox(height: 12),

            // Details Row
            Row(
              children: [
                // Price & Quantity
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatCurrency(price)} $currency',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        Text(
                          '${l10n.qty ?? 'Qty'}: $quantity',
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
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.total ?? 'Total',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                          ),
                        ),
                        Text(
                          '${_formatCurrency(totalAmount)} $currency',
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

            // Dynamic Attributes Row - UPDATED TO BE DYNAMIC
            if (selectedAttributes.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDynamicAttributesSection(selectedAttributes, l10n, isDark),
            ],
          ],
        ),
      ),
    );
  }

// Add this new helper method to build dynamic attributes section
  Widget _buildDynamicAttributesSection(Map<String, dynamic> selectedAttributes,
      AppLocalizations l10n, bool isDark) {
    final List<Widget> attributeChips = [];

    // Define color palette for different attribute types
    final List<Map<String, dynamic>> colorPalette = [
      {'bg': const Color(0xFF6366F1), 'name': 'primary'},
      {'bg': const Color(0xFF8B5CF6), 'name': 'purple'},
      {'bg': const Color(0xFF10B981), 'name': 'green'},
      {'bg': const Color(0xFFF59E0B), 'name': 'amber'},
      {'bg': const Color(0xFFEF4444), 'name': 'red'},
      {'bg': const Color(0xFF3B82F6), 'name': 'blue'},
      {'bg': const Color(0xFF06B6D4), 'name': 'cyan'},
    ];

    int colorIndex = 0;

    // System fields list (same as before)
    final systemFields = {
      // Document identifiers
      'productId', 'orderId', 'buyerId', 'sellerId',
      // Timestamps
      'timestamp', 'addedAt', 'updatedAt',
      // Images (not user selections)
      'selectedColorImage', 'productImage',
      // Pricing fields (calculated by cart/system)
      'price', 'finalPrice', 'calculatedUnitPrice', 'calculatedTotal',
      'unitPrice', 'totalPrice', 'currency',
      // Bundle/sale system fields
      'isBundleItem', 'bundleInfo', 'salePreferences', 'isBundle',
      'bundleId', 'mainProductPrice', 'bundlePrice',
      // Seller info (displayed elsewhere)
      'sellerName', 'isShop', 'shopId',
      // Product metadata (not user choices)
      'productName', 'brandModel', 'brand', 'category', 'subcategory',
      'subsubcategory', 'condition', 'averageRating', 'productAverageRating',
      'reviewCount', 'productReviewCount', 'gender', 'clothingType',
      'clothingFit',
      // Order/shipping status
      'shipmentStatus', 'deliveryOption', 'needsProductReview',
      'needsSellerReview', 'needsAnyReview',
      // System quantities
      'quantity', 'availableStock', 'maxQuantityAllowed', 'ourComission',
      'sellerContactNo', 'showSellerHeader',
      'clothingTypes',
      'pantFabricTypes',
      'pantFabricType',
    };

    // Process user-selected attributes (same as before)
    selectedAttributes.forEach((key, value) {
      if (value == null ||
          value.toString().isEmpty ||
          (value is List && value.isEmpty) ||
          systemFields.contains(key)) {
        return;
      }

      if (systemFields.contains(key)) {
        return;
      }

      try {
        // Use AttributeLocalizationUtils for proper localization
        final localizedKey =
            AttributeLocalizationUtils.getLocalizedAttributeTitle(key, l10n);
        final localizedValue =
            AttributeLocalizationUtils.getLocalizedAttributeValue(
                key, value, l10n);

        // Get color for this attribute
        final currentColor =
            colorPalette[colorIndex % colorPalette.length]['bg'] as Color;
        colorIndex++;

        attributeChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: currentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: currentColor.withOpacity(0.2),
              ),
            ),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$localizedKey: ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: currentColor,
                    ),
                  ),
                  TextSpan(
                    text: localizedValue,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: currentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        // Fallback for any localization errors
        final fallbackColor =
            colorPalette[colorIndex % colorPalette.length]['bg'] as Color;
        colorIndex++;

        attributeChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: fallbackColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$key: $value',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fallbackColor,
              ),
            ),
          ),
        );
      }
    });

    if (attributeChips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark ? Colors.white.withOpacity(0.02) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.productDetails ?? 'Product Details',
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
            children: attributeChips,
          ),
        ],
      ),
    );
  }

  Widget _buildShippingAddress(bool isDark) {
    if (_orderData == null || _orderData!['address'] == null) {
      return const SizedBox.shrink();
    }

    final address = _orderData!['address'] as Map<String, dynamic>;
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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
      ),
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
                      color: const Color(0xFF10B981).withOpacity(0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.shippingAddress ?? 'Shipping Address',
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
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${address['addressLine1'] ?? ''}${address['addressLine2'] != null && address['addressLine2'].toString().isNotEmpty ? ', ${address['addressLine2']}' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address['city'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (address['phoneNumber'] != null &&
                      address['phoneNumber'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.phone,
                            size: 12,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          address['phoneNumber'] ?? '',
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

  // Add these helper methods to the _ShipmentStatusScreenState class:

  String _getLocalizedDeliveryOption(String option, AppLocalizations l10n) {
    switch (option) {
      case 'gelal':
        return l10n.deliveryOption1 ?? 'Gel Al (Pick Up)';
      case 'express':
        return l10n.deliveryOption2 ?? 'Express Delivery';
      case 'normal':
      default:
        return l10n.deliveryOption3 ?? 'Normal Delivery';
    }
  }

  Color _getDeliveryOptionColor(String deliveryOption) {
    switch (deliveryOption) {
      case 'express':
        return Colors.orange;
      case 'gelal':
        return Colors.blue;
      case 'normal':
      default:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildOrderSummary(bool isDark) {
    if (_orderData == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    // Get pricing data
    final itemsSubtotal =
        (_orderData!['itemsSubtotal'] ?? _orderData!['totalPrice'] ?? 0)
            .toDouble();
    final deliveryPrice = (_orderData!['deliveryPrice'] ?? 0).toDouble();
    final totalPrice = (_orderData!['totalPrice'] ?? 0).toDouble();
    final currency = _orderData!['currency'] ?? 'TL';
    final deliveryOption = _orderData!['deliveryOption'] as String? ?? 'normal';

    // Get coupon/benefit data
    final couponCode = _orderData!['couponCode'] as String?;
    final couponDiscount = (_orderData!['couponDiscount'] ?? 0).toDouble();
    final freeShippingApplied =
        _orderData!['freeShippingApplied'] as bool? ?? false;
    final originalDeliveryPrice =
        (_orderData!['originalDeliveryPrice'] ?? deliveryPrice).toDouble();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
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
      ),
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
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt,
                    color: Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.orderSummary ?? 'Order Summary',
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
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Subtotal row
                  _buildSummaryRow(
                    l10n.subtotal ?? 'Subtotal',
                    '${_formatCurrency(itemsSubtotal)} $currency',
                    isDark,
                  ),

                  // Coupon discount row (if applied)
                  if (couponDiscount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_offer,
                              size: 14,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.couponDiscount ?? 'Coupon Discount',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '-${_formatCurrency(couponDiscount)} $currency',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Delivery row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (freeShippingApplied) ...[
                            Icon(
                              Icons.card_giftcard,
                              size: 14,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            l10n.delivery ?? 'Delivery',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getDeliveryOptionColor(deliveryOption)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getLocalizedDeliveryOption(deliveryOption, l10n),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: _getDeliveryOptionColor(deliveryOption),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Show original price struck through if free shipping applied
                          if (freeShippingApplied &&
                              originalDeliveryPrice > 0) ...[
                            Text(
                              '${_formatCurrency(originalDeliveryPrice)} $currency',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[400],
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            deliveryPrice == 0
                                ? l10n.free ?? 'Free'
                                : '${_formatCurrency(deliveryPrice)} $currency',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: deliveryPrice == 0
                                  ? const Color(0xFF10B981)
                                  : (isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1A1A)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Free shipping benefit label
                  if (freeShippingApplied) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check,
                              size: 12,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.freeShippingBenefit ??
                                  'Free Shipping Benefit',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
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

                  // Total row
                  _buildSummaryRow(
                    l10n.total ?? 'Total',
                    '${_formatCurrency(totalPrice)} $currency',
                    isDark,
                    isTotal: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  color: Color(0xFF6366F1),
                )
              : TextStyle(
                  fontSize: 11,
                  color: valueColor ??
                      (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                  fontWeight: FontWeight.w600,
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildModernSliverAppBar(context, l10n, isDark),
          _isLoading
              ? SliverFillRemaining(child: _buildLoadingState(isDark))
              : _error != null
                  ? SliverFillRemaining(child: _buildErrorState(l10n, isDark))
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        _buildOrderHeader(isDark),
                        _buildOrderItems(isDark),
                        _buildShippingAddress(isDark),
                        _buildOrderSummary(isDark),
                        const SizedBox(height: 32),
                      ]),
                    ),
        ],
      ),
    );
  }
}
