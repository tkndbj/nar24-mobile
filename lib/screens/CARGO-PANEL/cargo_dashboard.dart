import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../generated/l10n/app_localizations.dart';
import 'cargo_route.dart';
import 'package:Nar24/auth_service.dart';
import 'cargo_done_operations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

class CargoDashboard extends StatefulWidget {
  const CargoDashboard({Key? key}) : super(key: key);

  @override
  State<CargoDashboard> createState() => _CargoDashboardState();
}

class _CargoDashboardState extends State<CargoDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _gatheringItems = [];
  List<Map<String, dynamic>> _distributionOrders = [];
  String _cargoUserName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCargoData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCargoData() async {
    setState(() => _isLoading = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      _cargoUserName = userDoc.data()?['displayName'] ?? '';

      // FIXED: Only get items with 'assigned' status for gathering
      // Items with 'gathered' status should not appear as they've already been picked up
      final gatheringQuery = await FirebaseFirestore.instance
          .collectionGroup('items')
          .where('gatheredBy', isEqualTo: userId)
          .where('gatheringStatus',
              isEqualTo: 'assigned') // Only assigned items need gathering
          .get();

      _gatheringItems = await Future.wait(
        gatheringQuery.docs.map((doc) => _processGatheringItem(doc)).toList(),
      );

      // UPDATED: Get orders with 'assigned' status AND incomplete delivered orders
      final distributionQuery = await FirebaseFirestore.instance
          .collection('orders')
          .where('distributedBy', isEqualTo: userId)
          .where('distributionStatus', whereIn: ['assigned', 'delivered'])
          .orderBy('timestamp', descending: true)
          .get();

      _distributionOrders = await Future.wait(
        distributionQuery.docs
            .map((doc) => _processDistributionOrder(doc))
            .toList(),
      );

// Filter to only show incomplete delivered orders and assigned orders
      _distributionOrders = _distributionOrders.where((order) {
        final status = order['distributionStatus'];
        if (status == 'assigned') {
          return true; // Always show assigned
        }
        if (status == 'delivered') {
          // Only show delivered if order is incomplete
          return order['allItemsGathered'] == false;
        }
        return false;
      }).toList();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Error loading data: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _processGatheringItem(
      QueryDocumentSnapshot itemDoc) async {
    final itemData = itemDoc.data() as Map<String, dynamic>;
    final orderId = itemDoc.reference.parent.parent?.id ?? '';

    return {
      'itemId': itemDoc.id,
      'orderId': orderId,
      'productName': itemData['productName'] ?? '',
      'quantity': itemData['quantity'] ?? 1,
      'sellerName': itemData['sellerName'] ?? '',
      'sellerId': itemData['sellerId'] ?? '',
      'isShopProduct': itemData['isShopProduct'] ?? false,
      'buyerName': itemData['buyerName'] ?? '',
      'gatheringStatus': itemData['gatheringStatus'] ?? 'assigned',
      'sellerAddress': itemData['sellerAddress'],
      'sellerContactNo': itemData['sellerContactNo'] ?? '',
      'timestamp': itemData['timestamp'],
      'gatheredBy': itemData['gatheredBy'],
      'deliveryOption': itemData['deliveryOption'] ?? 'normal',
      'warehouseNote': itemData['warehouseNote'],
    };
  }

  Future<Map<String, dynamic>> _processDistributionOrder(
      QueryDocumentSnapshot orderDoc) async {
    final orderData = orderDoc.data() as Map<String, dynamic>;

    final itemsSnapshot = await FirebaseFirestore.instance
        .collection('orders')
        .doc(orderDoc.id)
        .collection('items')
        .get();

    final items = itemsSnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'productName': data['productName'] ?? '',
        'quantity': data['quantity'] ?? 1,
        'gatheringStatus': data['gatheringStatus'],
      };
    }).toList();

    return {
      'orderId': orderDoc.id,
      'buyerId': orderData['buyerId'] ?? '',
      'buyerName': orderData['buyerName'] ?? '',
      'address': orderData['address'],
      'pickupPoint': orderData['pickupPoint'],
      'deliveryOption': orderData['deliveryOption'] ?? 'normal',
      'distributionStatus': orderData['distributionStatus'] ?? 'assigned',
      'distributedBy': orderData['distributedBy'],
      'items': items,
      'timestamp': orderData['timestamp'],
      'warehouseNote': orderData['warehouseNote'],
      'allItemsGathered': orderData['allItemsGathered'] ?? true,
    };
  }

  Future<void> _markItemAsGathered(String orderId, String itemId) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .doc(itemId)
          .update({
        'gatheringStatus': 'gathered',
      });

      _showSuccess(AppLocalizations.of(context).itemMarkedAsGathered);
      _loadCargoData();
    } catch (e) {
      _showError('Error updating item: $e');
    }
  }

  Future<void> _markItemAsArrived(String orderId, String itemId) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .doc(itemId)
          .update({
        'gatheringStatus': 'at_warehouse',
        'arrivedAt': Timestamp.now(),
      });

      _showSuccess(AppLocalizations.of(context).itemMarkedAsArrived);
      _loadCargoData();
    } catch (e) {
      _showError('Error updating item: $e');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showError('Could not launch phone dialer');
      }
    } catch (e) {
      _showError('Error making call: $e');
    }
  }

  void _showWarehouseNote(Map<String, dynamic> data, bool isItem) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final note = data['warehouseNote'] ?? '';

    if (note.isEmpty) {
      _showError('No warehouse note available');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              FeatherIcons.fileText,
              color: isItem ? Colors.orange : Colors.blue,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Warehouse Note',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: Text(
              note,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _markOrderAsDelivered(String orderId) async {
    try {
      // First, get the order details to check if it's incomplete
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      final orderData = orderDoc.data();
      final isIncomplete = orderData?['allItemsGathered'] == false;

      // Prepare update data
      final updateData = <String, dynamic>{
        'distributionStatus': 'delivered',
        'deliveredAt': Timestamp.now(),
      };

      // If order is incomplete (partial delivery), also unassign the distributor
      if (isIncomplete) {
        updateData['distributedBy'] = null;
        updateData['distributedByName'] = null;
        updateData['distributedAt'] = null;

        print(
            'Partial delivery detected - unassigning distributor for order $orderId');
      }

      // Update the order
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update(updateData);

      // Show appropriate success message
      if (isIncomplete) {
        _showSuccess(
            '${AppLocalizations.of(context).markedAsDelivered} (Partial delivery - distributor unassigned)');
      } else {
        _showSuccess(AppLocalizations.of(context).markedAsDelivered);
      }

      _loadCargoData();
    } catch (e) {
      _showError('Error updating order: $e');
    }
  }

  void _showItemDetails(Map<String, dynamic> item) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              FeatherIcons.package,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['productName'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      icon: FeatherIcons.user,
                      label: l10n.seller,
                      value: item['sellerName'],
                      color: Colors.blue,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: FeatherIcons.shoppingBag,
                      label: l10n.quantity,
                      value: 'x${item['quantity']}',
                      color: Colors.purple,
                      isDark: isDark,
                    ),
                    if (item['sellerAddress'] != null) ...[
                      const SizedBox(height: 10),
                      _buildInfoRow(
                        icon: FeatherIcons.mapPin,
                        label: l10n.address,
                        value:
                            '${item['sellerAddress']['addressLine1']}, ${item['sellerAddress']['city']}',
                        color: Colors.green,
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: FeatherIcons.user,
                      label: 'Buyer',
                      value: item['buyerName'],
                      color: Colors.teal,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Column(
                children: [
                  if (item['gatheringStatus'] == 'assigned')
                    _buildButton(
                      label: l10n.markAsGathered,
                      icon: FeatherIcons.check,
                      color: Colors.blue,
                      onPressed: () {
                        Navigator.pop(context);
                        _markItemAsGathered(item['orderId'], item['itemId']);
                      },
                    ),
                  if (item['gatheringStatus'] == 'gathered')
                    _buildButton(
                      label: l10n.markAsArrived,
                      icon: FeatherIcons.checkCircle,
                      color: Colors.green,
                      onPressed: () {
                        Navigator.pop(context);
                        _markItemAsArrived(item['orderId'], item['itemId']);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(Map<String, dynamic> item, bool isDark) {
    final hasNote = item['warehouseNote'] != null &&
        item['warehouseNote'].toString().trim().isNotEmpty;

    return InkWell(
      onTap: () => _showItemDetails(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              FeatherIcons.package,
              size: 16,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item['productName'],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildDeliveryLabel(item['deliveryOption']),
                    ],
                  ),
                  Text(
                    'For: ${item['buyerName']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (hasNote)
              IconButton(
                icon: const Icon(FeatherIcons.fileText, size: 16),
                color: Colors.orange,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () => _showWarehouseNote(item, true),
                tooltip: 'View warehouse note',
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'x${item['quantity']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryLabel(String? deliveryOption) {
    final isExpress = deliveryOption == 'express';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: isExpress
            ? const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF1493)],
              )
            : null,
        color: isExpress ? null : Colors.green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isExpress ? 'Express' : 'Normal',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FeatherIcons.alertCircle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FeatherIcons.checkCircle, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(FeatherIcons.logOut, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Text(
              l10n.confirmLogout ?? 'Confirm Logout',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: Text(
          l10n.logoutMessage ?? 'Are you sure you want to logout?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(l10n.logout ?? 'Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      await _performLogout(context);
    }
  }

  Future<void> _performLogout(BuildContext context) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final authService = AuthService();
      await authService.logout();

      if (context.mounted) {
        context.go('/');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showError('Logout failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                FeatherIcons.truck,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cargoPanel,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_cargoUserName.isNotEmpty)
                    Text(
                      _cargoUserName,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(FeatherIcons.clock, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CargoDoneOperations(),
                ),
              ).then((_) {
                // Refresh data when returning from completed operations
                _loadCargoData();
              });
            },
            tooltip: l10n.completedOperations ?? 'Completed Operations',
          ),
          IconButton(
            icon: const Icon(FeatherIcons.logOut, size: 20),
            onPressed: () => _confirmLogout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor:
                    isDark ? Colors.white60 : Colors.grey.shade700,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(FeatherIcons.package, size: 16),
                        const SizedBox(width: 6),
                        Text(l10n.gathering),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(FeatherIcons.truck, size: 16),
                        const SizedBox(width: 6),
                        Text(l10n.distribution),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGatheringList(),
                      _buildDistributionList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatheringList() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_gatheringItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FeatherIcons.inbox,
              size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noItemsAssigned,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final groupedItems = <String, List<Map<String, dynamic>>>{};
    for (final item in _gatheringItems) {
      final key = item['sellerId'];
      groupedItems[key] = groupedItems[key] ?? [];
      groupedItems[key]!.add(item);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CargoRoute(
                      orders: _gatheringItems,
                      isGatherer: true,
                    ),
                  ),
                );
              },
              icon: const Icon(FeatherIcons.navigation, size: 18),
              label: Text(l10n.createRoute),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCargoData,
            color: Colors.orange,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: groupedItems.length,
              itemBuilder: (context, index) {
                final sellerId = groupedItems.keys.elementAt(index);
                final items = groupedItems[sellerId]!;
                return _buildSellerCard(items, isDark);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSellerCard(List<Map<String, dynamic>> items, bool isDark) {
    final firstItem = items.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: firstItem['isShopProduct']
                  ? Colors.purple.shade50
                  : Colors.blue.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: firstItem['isShopProduct']
                        ? Colors.purple
                        : Colors.blue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    firstItem['isShopProduct']
                        ? FeatherIcons.shoppingBag
                        : FeatherIcons.user,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstItem['sellerName'],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (firstItem['sellerAddress'] != null)
                        Row(
                          children: [
                            Icon(
                              FeatherIcons.mapPin,
                              size: 10,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                firstItem['sellerAddress']['addressLine1'] ??
                                    '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(FeatherIcons.phone, size: 16),
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      final phoneNumber = firstItem['sellerContactNo'];
                      if (phoneNumber != null &&
                          phoneNumber.toString().isNotEmpty) {
                        _makePhoneCall(phoneNumber.toString());
                      } else {
                        _showError('Phone number not available');
                      }
                    },
                    tooltip: 'Call ${firstItem['sellerName']}',
                  ),
                ),
              ],
            ),
          ),
          ...items.map((item) => _buildItemTile(item, isDark)),
        ],
      ),
    );
  }

  /// Groups orders going to the same address into combined stops for routing
  List<Map<String, dynamic>> _groupOrdersForRoute(
      List<Map<String, dynamic>> orders) {
    final groupedOrders = <String, List<Map<String, dynamic>>>{};

    for (final order in orders) {
      final key = _getDeliveryAddressKey(order);
      groupedOrders[key] = groupedOrders[key] ?? [];
      groupedOrders[key]!.add(order);
    }

    // Convert grouped orders into single stop entries
    return groupedOrders.values.map((ordersAtSameAddress) {
      final firstOrder = ordersAtSameAddress.first;

      // Combine all items from all orders at this address
      final allItems = <Map<String, dynamic>>[];
      final allOrderIds = <String>[];

      for (final order in ordersAtSameAddress) {
        allOrderIds.add(order['orderId']);
        final items = order['items'] as List? ?? [];
        for (final item in items) {
          allItems.add({
            ...item,
            'orderId':
                order['orderId'], // Track which order each item belongs to
          });
        }
      }

      // Return a combined stop with all order info
      return {
        'orderId': firstOrder['orderId'], // Primary order ID (for QR scan)
        'orderIds': allOrderIds, // All order IDs at this stop
        'buyerId': firstOrder['buyerId'],
        'buyerName': firstOrder['buyerName'],
        'address': firstOrder['address'],
        'pickupPoint': firstOrder['pickupPoint'],
        'deliveryOption': _getPriorityDeliveryOption(ordersAtSameAddress),
        'distributionStatus': firstOrder['distributionStatus'],
        'distributedBy': firstOrder['distributedBy'],
        'items': allItems,
        'timestamp': firstOrder['timestamp'],
        'warehouseNote': _combineWarehouseNotes(ordersAtSameAddress),
        'allItemsGathered':
            ordersAtSameAddress.every((o) => o['allItemsGathered'] == true),
        'isMultipleOrders': ordersAtSameAddress.length > 1,
        'orderCount': ordersAtSameAddress.length,
      };
    }).toList();
  }

  /// Gets the highest priority delivery option from a group of orders
  String _getPriorityDeliveryOption(List<Map<String, dynamic>> orders) {
    // Express takes priority over normal
    for (final order in orders) {
      if (order['deliveryOption'] == 'express') {
        return 'express';
      }
    }
    return orders.first['deliveryOption'] ?? 'normal';
  }

  /// Combines warehouse notes from multiple orders
  String? _combineWarehouseNotes(List<Map<String, dynamic>> orders) {
    final notes = orders
        .where((o) =>
            o['warehouseNote'] != null &&
            o['warehouseNote'].toString().trim().isNotEmpty)
        .map((o) => '• ${o['warehouseNote']}')
        .toList();

    if (notes.isEmpty) return null;
    return notes.join('\n');
  }

  /// Generates a unique key for grouping orders by buyer + address
  String _getDeliveryAddressKey(Map<String, dynamic> order) {
    final buyerId = order['buyerId'] ?? '';

    if (order['address'] != null) {
      final addr = order['address'];
      final line1 =
          (addr['addressLine1'] ?? '').toString().trim().toLowerCase();
      final city = (addr['city'] ?? '').toString().trim().toLowerCase();

      // Group by buyerId + main address components (ignore phone, line2 variations)
      return '$buyerId|$line1|$city';
    } else if (order['pickupPoint'] != null) {
      final pickup = order['pickupPoint'];
      final pickupId =
          (pickup['id'] ?? pickup['pickupPointId'] ?? '').toString();

      return '$buyerId|pickup|$pickupId';
    }

    // Fallback
    return '$buyerId|${order['orderId']}';
  }

  Widget _buildDistributionList() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_distributionOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FeatherIcons.inbox,
              size: 48,
              color: isDark ? Colors.white24 : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noOrdersAssigned,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Group orders by delivery address (same buyer + same address)
    final groupedOrders = <String, List<Map<String, dynamic>>>{};
    for (final order in _distributionOrders) {
      final key = _getDeliveryAddressKey(order);
      groupedOrders[key] = groupedOrders[key] ?? [];
      groupedOrders[key]!.add(order);
    }

    final groupedOrdersList = groupedOrders.values.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                // Group orders by delivery address for route optimization
                final groupedForRoute =
                    _groupOrdersForRoute(_distributionOrders);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CargoRoute(
                      orders: groupedForRoute,
                      isGatherer: false,
                    ),
                  ),
                );
              },
              icon: const Icon(FeatherIcons.navigation, size: 18),
              label: Text(l10n.createRoute),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadCargoData,
            color: Colors.blue,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: groupedOrdersList.length,
              itemBuilder: (context, index) {
                final ordersGroup = groupedOrdersList[index];
                return _buildGroupedOrdersCard(ordersGroup, isDark);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Builds a card displaying grouped orders going to the same address
  Widget _buildGroupedOrdersCard(
      List<Map<String, dynamic>> orders, bool isDark) {
    final l10n = AppLocalizations.of(context);
    final firstOrder = orders.first;
    final totalOrders = orders.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with buyer info and address
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        FeatherIcons.user,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  firstOrder['buyerName'],
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (totalOrders > 1) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$totalOrders ${l10n.orders}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (firstOrder['address'] != null ||
                              firstOrder['pickupPoint'] != null)
                            Row(
                              children: [
                                Icon(
                                  FeatherIcons.mapPin,
                                  size: 10,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _formatOrderAddress(firstOrder),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // Phone call button
                    if (firstOrder['address'] != null &&
                        firstOrder['address']['phoneNumber'] != null)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: const Icon(FeatherIcons.phone, size: 16),
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            final phoneNumber =
                                firstOrder['address']['phoneNumber'];
                            if (phoneNumber != null &&
                                phoneNumber.toString().isNotEmpty) {
                              _makePhoneCall(phoneNumber.toString());
                            } else {
                              _showError('Phone number not available');
                            }
                          },
                          tooltip: 'Call ${firstOrder['buyerName']}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // List of orders in this group
          ...orders.map(
              (order) => _buildOrderTile(order, isDark, orders.length > 1)),
        ],
      ),
    );
  }

  /// Builds a single order tile within a grouped card
  Widget _buildOrderTile(
      Map<String, dynamic> order, bool isDark, bool showDivider) {
    final l10n = AppLocalizations.of(context);
    final hasNote = order['warehouseNote'] != null &&
        order['warehouseNote'].toString().trim().isNotEmpty;

    // Get items ready for delivery (at_warehouse status)
    final allItems = order['items'] as List? ?? [];
    final itemsToShow = allItems
        .where((item) =>
            item['gatheringStatus'] == 'at_warehouse' ||
            item['gatheringStatus'] == null)
        .toList();
    final hasItemsReady = itemsToShow.isNotEmpty;
    final isIncomplete = order['allItemsGathered'] == false;

    return InkWell(
      onTap: () => _showDeliveryConfirmDialog(order),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order header row
            Row(
              children: [
                Icon(
                  FeatherIcons.shoppingBag,
                  size: 14,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '#${order['orderId'].toString().substring(0, 8)}...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildDeliveryLabel(order['deliveryOption']),
                      if (isIncomplete) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Partial',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasNote)
                  IconButton(
                    icon: const Icon(FeatherIcons.fileText, size: 14),
                    color: Colors.blue,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showWarehouseNote(order, false),
                    tooltip: 'View warehouse note',
                  ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    FeatherIcons.check,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            // Items list
            if (hasItemsReady) ...[
              const SizedBox(height: 8),
              ...itemsToShow.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 22),
                        Icon(
                          FeatherIcons.package,
                          size: 12,
                          color: Colors.orange.shade400,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item['productName'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'x${item['quantity']}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ] else if (isIncomplete) ...[
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.only(left: 22),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(FeatherIcons.alertCircle,
                        size: 12, color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.missingItemsInOrder,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.amber.shade800,
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

  /// Shows confirmation dialog for marking an order as delivered
  void _showDeliveryConfirmDialog(Map<String, dynamic> order) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            const Icon(FeatherIcons.checkCircle, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Text(
              l10n.confirmDelivered,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: Text(
          '${l10n.markOrderAsDelivered}?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _markOrderAsDelivered(order['orderId']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  String _formatOrderAddress(Map<String, dynamic> order) {
    if (order['address'] != null) {
      final addr = order['address'];
      final line1 = addr['addressLine1'] ?? '';
      final line2 = addr['addressLine2'] ?? '';
      final city = addr['city'] ?? '';

      if (line2.isNotEmpty) {
        return '$line1, $line2, $city';
      }
      return '$line1, $city';
    } else if (order['pickupPoint'] != null) {
      final pickup = order['pickupPoint'];
      return pickup['pickupPointName'] ?? '';
    }
    return '-';
  }
}
