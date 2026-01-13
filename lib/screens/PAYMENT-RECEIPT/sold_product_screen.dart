import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

class SoldProductsScreen extends StatefulWidget {
  final String? orderId; // Optional - if null, shows all sold products

  const SoldProductsScreen({
    Key? key,
    this.orderId,
  }) : super(key: key);

  @override
  State<SoldProductsScreen> createState() => _SoldProductsScreenState();
}

class _SoldProductsScreenState extends State<SoldProductsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  Stream<QuerySnapshot> _buildQuery() {
    if (widget.orderId != null) {
      // For specific order, query the items subcollection directly
      return _firestore
          .collection('orders')
          .doc(widget.orderId)
          .collection('items')
          .where('sellerId', isEqualTo: _currentUserId)
          .where('shopId', isNull: true) // Only products, not shop_products
          .orderBy('timestamp', descending: true)
          .snapshots();
    } else {
      // For all sold products, we need to use collectionGroup but filter by seller
      return _firestore
          .collectionGroup('items')
          .where('sellerId', isEqualTo: _currentUserId)
          .where('shopId', isNull: true) // Only products, not shop_products
          .orderBy('timestamp', descending: true)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildModernSliverAppBar(context, l10n, isDark),
          _currentUserId == null
              ? SliverFillRemaining(child: _buildSignInPrompt(l10n, isDark))
              : SliverToBoxAdapter(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _buildQuery(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingState(isDark);
                      }

                      if (snapshot.hasError) {
                        return _buildErrorState(l10n, isDark);
                      }

                      final soldItems = snapshot.data?.docs ?? [];

                      if (soldItems.isEmpty) {
                        return _buildEmptyState(l10n, isDark);
                      }

                      return _buildItemsList(soldItems, l10n, isDark);
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildModernSliverAppBar(BuildContext context, AppLocalizations l10n, bool isDark) {
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
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
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
              colors: [const Color(0xFF10B981), const Color(0xFF059669)],
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
                          widget.orderId != null ? l10n.orderDetails : l10n.soldProducts,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
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
                      Icons.inventory_2_outlined,
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

  Widget _buildSignInPrompt(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_circle_outlined,
              size: 32,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.pleaseSignIn,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Access your sold products dashboard',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: List.generate(5, (index) => Padding(
        padding: EdgeInsets.only(bottom: index == 4 ? 0 : 12),
        child: _buildShimmerCard(isDark),
      )),
    ),
  );
}

Widget _buildShimmerCard(bool isDark) {
  return Shimmer.fromColors(
    baseColor: isDark ? Color.fromARGB(255, 33, 31, 49)  : Colors.grey[300]!,
    highlightColor: isDark ? Color.fromARGB(255, 52, 48, 75)  : Colors.grey[100]!,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          // Header Row Shimmer
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 24,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Details Row Shimmer
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action Row Shimmer
          Row(
            children: [
              Container(
                height: 12,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),
              Container(
                height: 28,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ],
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
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.06),
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
            l10n.errorLoadingData(l10n.errorLoadingData),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Unable to load your sold products',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
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

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.06),
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
              color: const Color(0xFF6B7280).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 32,
              color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.orderId != null
                ? l10n.noItemsInThisOrder
                : l10n.noSoldProductsYet,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.orderId != null
                ? l10n.orderItemsWillAppearHere
                : l10n.soldProductsWillAppearHere,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(List<QueryDocumentSnapshot> soldItems, AppLocalizations l10n, bool isDark) {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: const Color(0xFF10B981),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: soldItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value.data() as Map<String, dynamic>;
            return Padding(
              padding: EdgeInsets.only(bottom: index == soldItems.length - 1 ? 0 : 12),
              child: _buildCompactSoldItemCard(context, item, l10n, isDark),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactSoldItemCard(
      BuildContext context, Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    final productName = item['productName'] ?? l10n.unknownProduct;
    final productImage = item['productImage'] ?? '';
    final price = (item['price'] ?? 0).toDouble();
    final quantity = item['quantity'] ?? 1;
    final currency = item['currency'] ?? 'TL';
    final buyerName = item['buyerName'] ?? l10n.unknownBuyer;
    final shipmentStatus = item['shipmentStatus'] ?? 'Pending';
    final timestamp = item['timestamp'] as Timestamp?;
    final selectedColor = item['selectedColor'];
    final selectedSize = item['selectedSize'];

    final totalAmount = price * quantity;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.04),
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
                          child: Image.network(
                            productImage,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.image_not_supported_outlined,
                                color: isDark ? Colors.grey[600] : Colors.grey[400],
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
                          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Product Sale',
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
                _buildCompactStatusChip(shipmentStatus, l10n, isDark),
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
                          '${NumberFormat('#,##0').format(price)} $currency',
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
                // Buyer
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.buyer ?? 'Buyer',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                          ),
                        ),
                        Text(
                          buyerName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
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

            // Variants & Date Row
            if (selectedColor != null || selectedSize != null || timestamp != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // Variants
                  if (selectedColor != null || selectedSize != null)
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (selectedColor != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                selectedColor,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          if (selectedSize != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                selectedSize,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Date
                  if (timestamp != null)
                    Text(
                      DateFormat('dd/MM/yy').format(timestamp.toDate()),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ],

            // Action Row
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${l10n.total}: ${NumberFormat('#,##0').format(totalAmount)} $currency',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const Spacer(),
                _buildCompactActionButton(context, item, l10n, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatusChip(String status, AppLocalizations l10n, bool isDark) {
    Color backgroundColor;
    Color textColor;
    String displayText;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFD69E2E);
        displayText = l10n.pending;
        icon = Icons.schedule;
        break;
      case 'shipped':
        backgroundColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF3B82F6);
        displayText = l10n.shipped;
        icon = Icons.local_shipping;
        break;
      case 'delivered':
        backgroundColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF10B981);
        displayText = l10n.delivered;
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        backgroundColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFFEF4444);
        displayText = l10n.cancelled;
        icon = Icons.cancel;
        break;
      default:
        backgroundColor = isDark ? Colors.grey[800]! : Colors.grey[100]!;
        textColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;
        displayText = status;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButton(
      BuildContext context, Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    final status = item['shipmentStatus'] ?? 'Pending';

    if (status.toLowerCase() == 'pending') {
      return ElevatedButton(
        onPressed: () => _showModernShipmentDialog(context, item, l10n, isDark),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          l10n.markAsShipped ?? 'Ship',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Completed',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
    );
  }

  void _showModernShipmentDialog(
      BuildContext context, Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    size: 24,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.markAsShipped,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.confirmShipmentMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                            ),
                          ),
                        ),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey[400] : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _updateShipmentStatus(item['orderId'], item['productId']);
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          l10n.confirm,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateShipmentStatus(String orderId, String productId) async {
    try {
      // Find the specific item document
      final itemsQuery = await _firestore
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .where('productId', isEqualTo: productId)
          .where('sellerId', isEqualTo: _currentUserId)
          .get();

      for (final doc in itemsQuery.docs) {
        await doc.reference.update({
          'shipmentStatus': 'Shipped',
          'shippedAt': FieldValue.serverTimestamp(),
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shipmentStatusUpdated,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).errorUpdatingStatus,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }
}