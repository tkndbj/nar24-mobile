import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shipment status enum matching Firestore structure
enum ShipmentStatus {
  pending, // gatheringStatus: 'pending' - waiting for cargo assignment
  collecting, // gatheringStatus: 'assigned' - cargo person assigned, going to collect
  inTransit, // gatheringStatus: 'gathered' - collected, on way to warehouse
  atWarehouse, // gatheringStatus: 'at_warehouse' - at warehouse, ready for distribution
  outForDelivery, // distributionStatus: 'assigned' - out for delivery
  delivered, // distributionStatus: 'delivered' - delivered to customer
  failed, // gatheringStatus: 'failed' OR distributionStatus: 'failed'
}

class ShipmentsTab extends StatefulWidget {
  const ShipmentsTab({Key? key}) : super(key: key);

  @override
  _ShipmentsTabState createState() => _ShipmentsTabState();
}

class _ShipmentsTabState extends State<ShipmentsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  // Filter state: null = all, otherwise specific status
  String? _activeFilter;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadShipments();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      if (provider.hasMoreShipments && !provider.isLoadingMoreShipments) {
        provider.loadMoreShipments(
          pageSize: _pageSize,
          statusFilter: _activeFilter,
        );
      }
    }
  }

  void _setFilter(String? filter) {
    if (_activeFilter == filter) return;

    setState(() {
      _activeFilter = filter;
    });

    _loadShipments();
  }

  Future<void> _loadShipments() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    await provider.resetAndLoadShipments(
      pageSize: _pageSize,
      statusFilter: _activeFilter,
    );
  }

  /// Determines the shipment status from item data
  /// Determines the shipment status from item data
  ShipmentStatus _getShipmentStatus(Map<String, dynamic> itemData) {
    final gatheringStatus = itemData['gatheringStatus'] as String?;

    // Check for failures first
    if (gatheringStatus == 'failed') {
      return ShipmentStatus.failed;
    }

    // Check if item was delivered
    // Option 1: gatheringStatus is 'delivered' (from QR scan)
    // Option 2: deliveredInPartial is true (from partial delivery)
    // Option 3: deliveryStatus is 'delivered'
    final deliveredInPartial = itemData['deliveredInPartial'] as bool? ?? false;
    final deliveryStatus = itemData['deliveryStatus'] as String?;

    if (gatheringStatus == 'delivered' ||
        deliveredInPartial ||
        deliveryStatus == 'delivered') {
      return ShipmentStatus.delivered;
    }

    // Check gathering status
    switch (gatheringStatus) {
      case 'at_warehouse':
        return ShipmentStatus.atWarehouse;
      case 'gathered':
        return ShipmentStatus.inTransit;
      case 'assigned':
        return ShipmentStatus.collecting;
      case 'pending':
      default:
        return ShipmentStatus.pending;
    }
  }

  /// Get localized status text
  String _getLocalizedStatus(ShipmentStatus status, AppLocalizations l10n) {
    switch (status) {
      case ShipmentStatus.pending:
        return l10n.shipmentPending;
      case ShipmentStatus.collecting:
        return l10n.shipmentCollecting;
      case ShipmentStatus.inTransit:
        return l10n.shipmentInTransit;
      case ShipmentStatus.atWarehouse:
        return l10n.shipmentAtWarehouse;
      case ShipmentStatus.outForDelivery:
        return l10n.shipmentOutForDelivery;
      case ShipmentStatus.delivered:
        return l10n.shipmentDelivered;
      case ShipmentStatus.failed:
        return l10n.shipmentFailed;
    }
  }

  /// Get status color
  Color _getStatusColor(ShipmentStatus status) {
    switch (status) {
      case ShipmentStatus.pending:
        return Colors.grey;
      case ShipmentStatus.collecting:
        return Colors.orange;
      case ShipmentStatus.inTransit:
        return Colors.blue;
      case ShipmentStatus.atWarehouse:
        return Colors.purple;
      case ShipmentStatus.outForDelivery:
        return Colors.indigo;
      case ShipmentStatus.delivered:
        return const Color(0xFF00A86B);
      case ShipmentStatus.failed:
        return Colors.red;
    }
  }

  /// Get status icon
  IconData _getStatusIcon(ShipmentStatus status) {
    switch (status) {
      case ShipmentStatus.pending:
        return Icons.schedule;
      case ShipmentStatus.collecting:
        return Icons.person_pin_circle;
      case ShipmentStatus.inTransit:
        return Icons.local_shipping;
      case ShipmentStatus.atWarehouse:
        return Icons.warehouse;
      case ShipmentStatus.outForDelivery:
        return Icons.delivery_dining;
      case ShipmentStatus.delivered:
        return Icons.check_circle;
      case ShipmentStatus.failed:
        return Icons.error;
    }
  }

  Widget _buildShimmerRow(bool isDarkMode) {
    return Shimmer.fromColors(
      baseColor: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDarkMode ? Colors.grey[600]! : Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 12,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerList(bool isDarkMode) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => _buildShimmerRow(isDarkMode),
    );
  }

  Widget _buildFilterChips(AppLocalizations l10n, bool isDarkMode) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: l10n.all,
            isSelected: _activeFilter == null,
            onTap: () => _setFilter(null),
            isDarkMode: isDarkMode,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.shipmentPending,
            isSelected: _activeFilter == 'pending',
            onTap: () => _setFilter('pending'),
            isDarkMode: isDarkMode,
            color: Colors.grey,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.shipmentInProgress,
            isSelected: _activeFilter == 'in_progress',
            onTap: () => _setFilter('in_progress'),
            isDarkMode: isDarkMode,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.shipmentDelivered,
            isSelected: _activeFilter == 'delivered',
            onTap: () => _setFilter('delivered'),
            isDarkMode: isDarkMode,
            color: const Color(0xFF00A86B),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      bottom: true,
      child: Column(
        children: [
          // Filter chips
          _buildFilterChips(l10n, isDarkMode),

          // Main content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadShipments,
              child: Consumer<SellerPanelProvider>(
                builder: (ctx, provider, _) {
                  final shipments = provider.shipments;

                  debugPrint(
                      '🔄 Consumer rebuild: ${shipments.length} shipments, isLoading: ${provider.isLoadingMoreShipments}');

                  // Show shimmer only during initial load when we have no data
                  if (shipments.isEmpty && provider.isLoadingMoreShipments) {
                    return _buildShimmerList(isDarkMode);
                  }

                  if (shipments.isEmpty) {
                    return _EmptyState(filter: _activeFilter);
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: shipments.length +
                        (provider.isLoadingMoreShipments ? 3 : 0),
                    itemBuilder: (ctx, idx) {
                      // Shimmer placeholders at the end
                      if (idx >= shipments.length) {
                        return _buildShimmerRow(isDarkMode);
                      }

                      final itemDoc = shipments[idx];
                      final itemData = itemDoc.data() as Map<String, dynamic>;

                      return _ShipmentItemCard(
                        key: ValueKey(itemDoc.id),
                        itemData: itemData,
                        status: _getShipmentStatus(itemData),
                        getLocalizedStatus: (status) =>
                            _getLocalizedStatus(status, l10n),
                        getStatusColor: _getStatusColor,
                        getStatusIcon: _getStatusIcon,
                        isDarkMode: isDarkMode,
                        l10n: l10n,
                        isLast: idx == shipments.length - 1,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

/// Filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDarkMode;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDarkMode,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? const Color(0xFF00A86B);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor
              : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor
                : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDarkMode ? Colors.white : Colors.black),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Shipment item card widget
class _ShipmentItemCard extends StatelessWidget {
  final Map<String, dynamic> itemData;
  final ShipmentStatus status;
  final String Function(ShipmentStatus) getLocalizedStatus;
  final Color Function(ShipmentStatus) getStatusColor;
  final IconData Function(ShipmentStatus) getStatusIcon;
  final bool isDarkMode;
  final AppLocalizations l10n;
  final bool isLast;

  const _ShipmentItemCard({
    super.key,
    required this.itemData,
    required this.status,
    required this.getLocalizedStatus,
    required this.getStatusColor,
    required this.getStatusIcon,
    required this.isDarkMode,
    required this.l10n,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final productName = itemData['productName'] as String? ?? 'Unnamed Product';
    final quantity = itemData['quantity'] as int? ?? 1;
    final buyerName = itemData['buyerName'] as String? ?? '';

    // Image handling
    final selectedColorImage = itemData['selectedColorImage'] as String?;
    final defaultImage = itemData['productImage'] as String? ?? '';
    final imageUrl = (selectedColorImage?.isNotEmpty == true)
        ? selectedColorImage!
        : defaultImage;

    // Delivery option
    final deliveryOption = itemData['deliveryOption'] as String? ?? 'normal';
    final isExpress = deliveryOption == 'express';

    final statusColor = getStatusColor(status);
    final statusText = getLocalizedStatus(status);
    final statusIcon = getStatusIcon(status);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            _ImagePlaceholder(isDarkMode: isDarkMode),
                        errorWidget: (_, __, ___) =>
                            _ImageError(isDarkMode: isDarkMode),
                      )
                    : _ImagePlaceholder(isDarkMode: isDarkMode),
              ),

              const SizedBox(width: 12),

              // Product details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      productName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Quantity and buyer
                    Row(
                      children: [
                        Text(
                          '${l10n.quantity}: $quantity',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                        if (buyerName.isNotEmpty) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              buyerName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Status and delivery type row
                    Row(
                      children: [
                        // Delivery type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isExpress
                                  ? [Colors.orange, Colors.pink]
                                  : [Colors.green, Colors.teal],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isExpress
                                ? l10n.expressDelivery
                                : l10n.normalDelivery,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                statusIcon,
                                size: 12,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          ),
      ],
    );
  }
}

/// Image placeholder widget
class _ImagePlaceholder extends StatelessWidget {
  final bool isDarkMode;

  const _ImagePlaceholder({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image,
        color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }
}

/// Image error widget
class _ImageError extends StatelessWidget {
  final bool isDarkMode;

  const _ImageError({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.broken_image,
        color: Colors.red,
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  final String? filter;

  const _EmptyState({this.filter});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    String message;
    if (filter == 'pending') {
      message = l10n.noPendingShipments;
    } else if (filter == 'in_progress') {
      message = l10n.noInProgressShipments;
    } else if (filter == 'delivered') {
      message = l10n.noDeliveredShipments;
    } else {
      message = l10n.noShipmentsFound;
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height - 250,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 80,
                color: isDark ? Colors.white24 : Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
