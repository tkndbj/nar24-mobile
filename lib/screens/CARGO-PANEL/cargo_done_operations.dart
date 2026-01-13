import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../generated/l10n/app_localizations.dart';

class CargoDoneOperations extends StatefulWidget {
  const CargoDoneOperations({Key? key}) : super(key: key);

  @override
  State<CargoDoneOperations> createState() => _CargoDoneOperationsState();
}

class _CargoDoneOperationsState extends State<CargoDoneOperations>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Gathered items state
  List<Map<String, dynamic>> _gatheredItems = [];
  bool _isLoadingGathered = false;
  bool _hasMoreGathered = true;
  DocumentSnapshot? _lastGatheredDoc;
  
  // Distributed orders state
  List<Map<String, dynamic>> _distributedOrders = [];
  bool _isLoadingDistributed = false;
  bool _hasMoreDistributed = true;
  DocumentSnapshot? _lastDistributedDoc;
  
  // Date filtering
  DateTime? _startDate;
  DateTime? _endDate;
  
  // Pagination limit
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      // Load data when switching tabs if needed
      if (_tabController.index == 0 && _gatheredItems.isEmpty) {
        _loadGatheredItems();
      } else if (_tabController.index == 1 && _distributedOrders.isEmpty) {
        _loadDistributedOrders();
      }
    }
  }

  Future<void> _loadInitialData() async {
    await _loadGatheredItems();
    await _loadDistributedOrders();
  }

  Future<void> _loadGatheredItems({bool refresh = false}) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;

  if (refresh) {
    setState(() {
      _gatheredItems.clear();
      _lastGatheredDoc = null;
      _hasMoreGathered = true;
    });
  }

  if (!_hasMoreGathered || _isLoadingGathered) return;

  setState(() => _isLoadingGathered = true);

  try {
    Query query = FirebaseFirestore.instance
        .collectionGroup('items')
        .where('gatheredBy', isEqualTo: userId)
        // REMOVED: .where('gatheringStatus', isEqualTo: 'gathered')
        .orderBy('gatheredAt', descending: true)
        .limit(_pageSize);

    // Apply date filters
    if (_startDate != null) {
      query = query.where('gatheredAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
    }
    if (_endDate != null) {
      final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      query = query.where('gatheredAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    // Pagination
    if (_lastGatheredDoc != null) {
      query = query.startAfterDocument(_lastGatheredDoc!);
    }

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      setState(() {
        _hasMoreGathered = false;
        _isLoadingGathered = false;
      });
      return;
    }

    final items = await Future.wait(
      snapshot.docs.map((doc) => _processGatheringItem(doc)).toList(),
    );

    setState(() {
      _gatheredItems.addAll(items);
      _lastGatheredDoc = snapshot.docs.last;
      _hasMoreGathered = snapshot.docs.length == _pageSize;
      _isLoadingGathered = false;
    });
  } catch (e) {
    setState(() => _isLoadingGathered = false);
    _showError('Error loading gathered items: $e');
  }
}

  Future<void> _loadDistributedOrders({bool refresh = false}) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    if (refresh) {
      setState(() {
        _distributedOrders.clear();
        _lastDistributedDoc = null;
        _hasMoreDistributed = true;
      });
    }

    if (!_hasMoreDistributed || _isLoadingDistributed) return;

    setState(() => _isLoadingDistributed = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('orders')
          .where('distributedBy', isEqualTo: userId)
          .where('distributionStatus', isEqualTo: 'delivered')
          .orderBy('deliveredAt', descending: true)
          .limit(_pageSize);

      // Apply date filters
      if (_startDate != null) {
        query = query.where('deliveredAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate!));
      }
      if (_endDate != null) {
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        query = query.where('deliveredAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
      }

      // Pagination
      if (_lastDistributedDoc != null) {
        query = query.startAfterDocument(_lastDistributedDoc!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _hasMoreDistributed = false;
          _isLoadingDistributed = false;
        });
        return;
      }

      final orders = await Future.wait(
        snapshot.docs.map((doc) => _processDistributionOrder(doc)).toList(),
      );

      setState(() {
        _distributedOrders.addAll(orders);
        _lastDistributedDoc = snapshot.docs.last;
        _hasMoreDistributed = snapshot.docs.length == _pageSize;
        _isLoadingDistributed = false;
      });
    } catch (e) {
      setState(() => _isLoadingDistributed = false);
      _showError('Error loading distributed orders: $e');
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
      'gatheredAt': itemData['gatheredAt'],
      'sellerAddress': itemData['sellerAddress'],
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
      };
    }).toList();

    return {
      'orderId': orderDoc.id,
      'buyerName': orderData['buyerName'] ?? '',
      'address': orderData['address'],
      'pickupPoint': orderData['pickupPoint'],
      'deliveredAt': orderData['deliveredAt'],
      'items': items,
    };
  }

  Future<void> _cancelGatheredItem(String orderId, String itemId) async {
    final l10n = AppLocalizations.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cancelOperation ?? 'Cancel Operation'),
        content: Text(l10n.cancelGatheredItemMessage ?? 
            'This will remove the item from gathered status and return it to assigned. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(l10n.confirm ?? 'Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .doc(itemId)
          .update({
        'gatheringStatus': 'assigned',
        'gatheredAt': FieldValue.delete(),
      });

      _showSuccess(l10n.operationCanceled ?? 'Operation canceled successfully');
      _loadGatheredItems(refresh: true);
    } catch (e) {
      _showError('Error canceling operation: $e');
    }
  }

  Future<void> _cancelDistributedOrder(String orderId) async {
    final l10n = AppLocalizations.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cancelOperation ?? 'Cancel Operation'),
        content: Text(l10n.cancelDistributedOrderMessage ?? 
            'This will remove the order from delivered status and return it to assigned. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text(l10n.confirm ?? 'Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({
        'distributionStatus': 'assigned',
        'deliveredAt': FieldValue.delete(),
      });

      _showSuccess(l10n.operationCanceled ?? 'Operation canceled successfully');
      _loadDistributedOrders(refresh: true);
    } catch (e) {
      _showError('Error canceling operation: $e');
    }
  }

  Future<void> _selectDateRange() async {
    final l10n = AppLocalizations.of(context);
    
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.orange,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });

      // Reload data with new filters
      if (_tabController.index == 0) {
        await _loadGatheredItems(refresh: true);
      } else {
        await _loadDistributedOrders(refresh: true);
      }
    }
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });

    // Reload data without filters
    if (_tabController.index == 0) {
      _loadGatheredItems(refresh: true);
    } else {
      _loadDistributedOrders(refresh: true);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
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
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
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
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        title: Text(
          l10n.completedOperations ?? 'Completed Operations',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Date filter button
          IconButton(
            icon: Icon(
              _startDate != null ? FeatherIcons.filter : FeatherIcons.calendar,
              color: _startDate != null ? Colors.orange : null,
              size: 20,
            ),
            onPressed: _selectDateRange,
            tooltip: l10n.filterByDate ?? 'Filter by Date',
          ),
          if (_startDate != null)
            IconButton(
              icon: const Icon(FeatherIcons.x, size: 20),
              onPressed: _clearDateFilter,
              tooltip: l10n.clearFilter ?? 'Clear Filter',
            ),
        ],
      ),
      body: Column(
        children: [
          // Date range indicator
          if (_startDate != null && _endDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  const Icon(FeatherIcons.calendar, size: 14, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_formatDate(Timestamp.fromDate(_startDate!))} - ${_formatDate(Timestamp.fromDate(_endDate!))}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Tabs
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
                        Text(l10n.gathered ?? 'Gathered'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(FeatherIcons.truck, size: 16),
                        const SizedBox(width: 6),
                        Text(l10n.distributed ?? 'Distributed'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGatheredList(isDark, l10n),
                _buildDistributedList(isDark, l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatheredList(bool isDark, AppLocalizations l10n) {
    if (_isLoadingGathered && _gatheredItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
      );
    }

    if (_gatheredItems.isEmpty) {
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
              l10n.noGatheredItems ?? 'No gathered items',
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

    // Group by seller
    final groupedItems = <String, List<Map<String, dynamic>>>{};
    for (final item in _gatheredItems) {
      final key = item['sellerId'];
      groupedItems[key] = groupedItems[key] ?? [];
      groupedItems[key]!.add(item);
    }

    return RefreshIndicator(
      onRefresh: () => _loadGatheredItems(refresh: true),
      color: Colors.orange,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent &&
              !_isLoadingGathered &&
              _hasMoreGathered) {
            _loadGatheredItems();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedItems.length + (_hasMoreGathered ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == groupedItems.length) {
              return _buildLoadingIndicator();
            }

            final sellerId = groupedItems.keys.elementAt(index);
            final items = groupedItems[sellerId]!;
            return _buildSellerCard(items, isDark, l10n);
          },
        ),
      ),
    );
  }

  Widget _buildSellerCard(
      List<Map<String, dynamic>> items, bool isDark, AppLocalizations l10n) {
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
              color: Colors.green.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green,
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
                      Text(
                        _formatDate(firstItem['gatheredAt']),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length} ${l10n.items ?? 'items'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...items.map((item) => _buildItemTile(item, isDark, l10n)),
        ],
      ),
    );
  }

  Widget _buildItemTile(
      Map<String, dynamic> item, bool isDark, AppLocalizations l10n) {
    return Container(
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
          const Icon(
            FeatherIcons.checkCircle,
            size: 16,
            color: Colors.green,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['productName'],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  '${l10n.buyer ?? 'Buyer'}: ${item['buyerName']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green,
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
          IconButton(
            icon: const Icon(FeatherIcons.rotateCcw, size: 18),
            onPressed: () => _cancelGatheredItem(item['orderId'], item['itemId']),
            color: Colors.orange,
            tooltip: l10n.cancelOperation ?? 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildDistributedList(bool isDark, AppLocalizations l10n) {
    if (_isLoadingDistributed && _distributedOrders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      );
    }

    if (_distributedOrders.isEmpty) {
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
              l10n.noDistributedOrders ?? 'No distributed orders',
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

    return RefreshIndicator(
      onRefresh: () => _loadDistributedOrders(refresh: true),
      color: Colors.blue,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent &&
              !_isLoadingDistributed &&
              _hasMoreDistributed) {
            _loadDistributedOrders();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _distributedOrders.length + (_hasMoreDistributed ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _distributedOrders.length) {
              return _buildLoadingIndicator();
            }

            final order = _distributedOrders[index];
            return _buildOrderCard(order, isDark, l10n);
          },
        ),
      ),
    );
  }

  Widget _buildOrderCard(
      Map<String, dynamic> order, bool isDark, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    FeatherIcons.checkCircle,
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
                        order['buyerName'],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        _formatDate(order['deliveredAt']),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(FeatherIcons.rotateCcw, size: 18),
                  onPressed: () => _cancelDistributedOrder(order['orderId']),
                  color: Colors.blue,
                  tooltip: l10n.cancelOperation ?? 'Cancel',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (order['address'] != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(FeatherIcons.mapPin, size: 14, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${order['address']['addressLine1']}, ${order['address']['city']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            ...List.generate(
              (order['items'] as List).length,
              (index) {
                final item = order['items'][index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(FeatherIcons.package,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['productName'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'x${item['quantity']}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              _tabController.index == 0 ? Colors.orange : Colors.blue,
            ),
          ),
        ),
      ),
    );
  }
}