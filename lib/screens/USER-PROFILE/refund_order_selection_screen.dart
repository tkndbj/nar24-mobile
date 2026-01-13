import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';

class RefundOrderSelectionScreen extends StatefulWidget {
  const RefundOrderSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RefundOrderSelectionScreen> createState() =>
      _RefundOrderSelectionScreenState();
}

class _RefundOrderSelectionScreenState
    extends State<RefundOrderSelectionScreen> {
  final _scrollController = ScrollController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Pagination state
  final List<Map<String, dynamic>> _orders = [];
  final Set<String> _loadedOrderIds = {};
  DocumentSnapshot? _lastDoc;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;

  // Selection state
  String? _selectedOrderId;
  Map<String, dynamic>? _selectedOrderData;

  // Constants
  static const int _pageSize = 15;
  static const double _loadMoreTriggerOffset = 0.8;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialOrders();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * _loadMoreTriggerOffset) {
      if (!_isLoadingMore && !_hasReachedEnd) {
        _loadMoreOrders();
      }
    }
  }

  Future<void> _loadInitialOrders() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    try {
      setState(() {
        _isLoadingInitial = true;
        _orders.clear();
        _loadedOrderIds.clear();
        _lastDoc = null;
        _hasReachedEnd = false;
      });

      await _fetchOrders(userId);

      if (mounted) {
        setState(() => _isLoadingInitial = false);
      }
    } catch (e) {
      debugPrint('Error loading initial orders: $e');
      if (mounted) {
        setState(() => _isLoadingInitial = false);
      }
    }
  }

  Future<void> _loadMoreOrders() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || _lastDoc == null) return;

    try {
      setState(() => _isLoadingMore = true);
      await _fetchOrders(userId);
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    } catch (e) {
      debugPrint('Error loading more orders: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _fetchOrders(String userId) async {
    Query<Map<String, dynamic>> query = _firestore
        .collectionGroup('items')
        .where('buyerId', isEqualTo: userId)
        .orderBy('timestamp', descending: true);

    if (_lastDoc != null) {
      query = query.startAfterDocument(_lastDoc!);
    }

    query = query.limit(_pageSize);

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      setState(() => _hasReachedEnd = true);
      return;
    }

    // Filter duplicates and add new orders
    final newOrders = snapshot.docs.where((doc) {
      return !_loadedOrderIds.contains(doc.id);
    }).map((doc) {
      _loadedOrderIds.add(doc.id);
      return {
        'id': doc.id,
        'data': doc.data(),
      };
    }).toList();

    setState(() {
      _orders.addAll(newOrders);
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasReachedEnd = snapshot.docs.length < _pageSize;
    });
  }

  Future<void> _refreshOrders() async {
    _selectedOrderId = null;
    _selectedOrderData = null;
    await _loadInitialOrders();
  }

  void _selectOrder(String orderId, Map<String, dynamic> orderData) {
    setState(() {
      if (_selectedOrderId == orderId) {
        _selectedOrderId = null;
        _selectedOrderData = null;
      } else {
        _selectedOrderId = orderId;
        _selectedOrderData = orderData;
      }
    });
  }

  void _confirmSelection() {
    if (_selectedOrderId == null || _selectedOrderData == null) return;

    // Navigate back with the selected order details
    context.pop({
      'orderId': _selectedOrderId,
      'orderData': _selectedOrderData,
    });
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            FeatherIcons.arrowLeft,
            color: theme.textTheme.bodyMedium?.color,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          localization.selectOrderForRefund,
          style: TextStyle(
            color: theme.textTheme.bodyMedium?.color,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(localization, theme, isDarkMode),
      bottomNavigationBar: _selectedOrderId != null
          ? _buildConfirmButton(localization, theme, isDarkMode)
          : null,
    );
  }

  Widget _buildBody(
      AppLocalizations localization, ThemeData theme, bool isDarkMode) {
    if (_isLoadingInitial) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.orange,
        ),
      );
    }

    if (_orders.isEmpty) {
      return _buildEmptyState(localization, isDarkMode);
    }

    return Column(
      children: [
        // Info banner
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.orange.withOpacity(0.1)
                : Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDarkMode
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.orange[200]!,
            ),
          ),
          child: Row(
            children: [
              Icon(
                FeatherIcons.info,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localization.selectOrderRefundInfo,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.orange[300] : Colors.orange[800],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Orders list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshOrders,
            color: Colors.orange,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _orders.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _orders.length) {
                  return _buildLoadingIndicator();
                }

                final order = _orders[index];
                return _buildOrderCard(
                  order['id'],
                  order['data'],
                  theme,
                  isDarkMode,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(
    String orderId,
    Map<String, dynamic> orderData,
    ThemeData theme,
    bool isDarkMode,
  ) {
    final isSelected = _selectedOrderId == orderId;
    final productName = orderData['productName'] as String? ?? 'Unknown Product';
    final price = (orderData['price'] as num?)?.toDouble() ?? 0.0;
    final currency = orderData['currency'] as String? ?? 'TRY';
    final quantity = (orderData['quantity'] as num?)?.toInt() ?? 1;
    final timestamp = orderData['timestamp'] as Timestamp?;
    final sellerName = orderData['sellerName'] as String? ?? 'Unknown Seller';
    
    // Get image
    final selectedColorImage = orderData['selectedColorImage'] as String?;
    final productImage = orderData['productImage'] as String? ?? '';
    final imageUrl = (selectedColorImage?.isNotEmpty == true) 
        ? selectedColorImage! 
        : productImage;

    String dateText = '';
    if (timestamp != null) {
      final date = timestamp.toDate();
      dateText = DateFormat('dd MMM yyyy, HH:mm').format(date);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 33, 31, 49)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? Colors.orange
              : isDarkMode
                  ? Colors.grey[800]!
                  : Colors.grey[200]!,
          width: isSelected ? 2 : 1,
        ),
       
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectOrder(orderId, orderData),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product image
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    image: imageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: imageUrl.isEmpty
                      ? Icon(
                          FeatherIcons.image,
                          color: Colors.grey[400],
                          size: 32,
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Order details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            FeatherIcons.user,
                            size: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              sellerName,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${price.toStringAsFixed(2)} $currency',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                            ),
                          ),
                          if (quantity > 1) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'x$quantity',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (dateText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              FeatherIcons.clock,
                              size: 11,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateText,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Selection indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.orange : Colors.grey[400]!,
                      width: 2,
                    ),
                    color: isSelected ? Colors.orange : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: CircularProgressIndicator(
          color: Colors.orange,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations localization, bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty-product.png',
              width: 150,
              height: 150,
              color: isDarkMode ? Colors.white.withOpacity(0.3) : null,
              colorBlendMode: isDarkMode ? BlendMode.srcATop : null,
            ),
            const SizedBox(height: 16),
            Text(
              localization.noOrdersForRefund,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              localization.noOrdersForRefundDesc,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDarkMode ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmButton(
      AppLocalizations localization, ThemeData theme, bool isDarkMode) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 33, 31, 49)
            : Colors.white,
      ),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.pink],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _confirmSelection,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    FeatherIcons.checkCircle,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    localization.confirmOrderSelection,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
}