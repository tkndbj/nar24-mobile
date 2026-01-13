import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import '../../utils/attribute_localization_utils.dart';

class SellerPanelOrderDetailsScreen extends StatefulWidget {
  final String? orderId; // Optional - if null, shows all sold shop products
  final String shopId; // Required - the shop ID

  const SellerPanelOrderDetailsScreen({
    Key? key,
    this.orderId,
    required this.shopId,
  }) : super(key: key);

  @override
  State<SellerPanelOrderDetailsScreen> createState() =>
      _SellerPanelOrderDetailsScreenState();
}

class _SellerPanelOrderDetailsScreenState
    extends State<SellerPanelOrderDetailsScreen> {
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
          .where('shopId', isEqualTo: widget.shopId)
          .orderBy('timestamp', descending: true)
          .snapshots();
    } else {
      // For all sold shop products, use collectionGroup and filter by shop
      return _firestore
          .collectionGroup('items')
          .where('shopId', isEqualTo: widget.shopId)
          .orderBy('timestamp', descending: true)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
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
                          widget.orderId != null
                              ? l10n.orderDetails
                              : l10n.shopSales,
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
                      Icons.store_outlined,
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_circle_outlined,
              size: 32,
              color: Color(0xFF6366F1),
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
            l10n.accessShopSalesDashboard,
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
        children: List.generate(
            5,
            (index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 4 ? 0 : 12),
                  child: _buildShimmerCard(isDark),
                )),
      ),
    );
  }

  Widget _buildShimmerCard(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.grey[300]!,
      highlightColor:
          isDark ? Color.fromARGB(255, 52, 48, 75) : Colors.grey[100]!,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.withOpacity(0.1),
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
                        width: 120,
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
                  width: 70,
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
            const SizedBox(height: 8),
            // Variants Row Shimmer
            Row(
              children: [
                Container(
                  height: 20,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  height: 20,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 10,
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
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
                  width: 50,
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
            l10n.errorLoadingData(l10n.error),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.unableToLoadSalesInfo,
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

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
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
              color: const Color(0xFF6B7280).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: 32,
              color: isDark ? Colors.grey[400] : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.orderId != null
                ? l10n.noItemsInThisOrder
                : l10n.noShopSalesYet,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.orderId != null
                ? l10n.orderDoesntContainShopItems
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

  Widget _buildItemsList(List<QueryDocumentSnapshot> soldItems,
      AppLocalizations l10n, bool isDark) {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: const Color(0xFF6366F1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: soldItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value.data() as Map<String, dynamic>;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: index == soldItems.length - 1 ? 0 : 12),
              child: _buildCompactSoldItemCard(context, item, l10n, isDark),
            );
          }).toList(),
        ),
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

  Widget _buildCompactSoldItemCard(BuildContext context,
      Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    final productName = item['productName'] ?? l10n.unknownProduct;
    final productImage = item['productImage'] ?? '';
    final price = (item['price'] ?? 0).toDouble();
    final quantity = item['quantity'] ?? 1;
    final currency = item['currency'] ?? 'TL';
    final buyerName = item['buyerName'] ?? l10n.unknownBuyer;
    final shipmentStatus = _getShipmentStatusFromItem(item);
    final timestamp = item['timestamp'] as Timestamp?;
    final orderId = item['orderId'] ?? '';

    // Get all selected attributes dynamically
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
                          child: Image.network(
                            productImage,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
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
                      if (orderId.isNotEmpty)
                        Text(
                          '#${orderId.substring(0, 8).toUpperCase()}',
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
                          '${l10n.qty}: $quantity',
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
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.buyer,
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

            // Dynamic Attributes & Date Row - UPDATED TO BE DYNAMIC
            const SizedBox(height: 8),
            _buildDynamicAttributesAndDateSection(
                selectedAttributes, timestamp, l10n, isDark),

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

// Add this new helper method to build dynamic attributes and date section
  Widget _buildDynamicAttributesAndDateSection(
      Map<String, dynamic> selectedAttributes,
      Timestamp? timestamp,
      AppLocalizations l10n,
      bool isDark) {
    final List<Widget> attributeChips = [];

    // Define color palette for different attribute types
    final List<Color> colorPalette = [
      const Color(0xFF6366F1), // primary
      const Color(0xFF8B5CF6), // purple
      const Color(0xFF10B981), // green
      const Color(0xFFF59E0B), // amber
      const Color(0xFF3B82F6), // blue
      const Color(0xFF06B6D4), // cyan
      const Color(0xFFEF4444), // red
    ];

    int colorIndex = 0;

    // Process all selectedAttributes dynamically
    selectedAttributes.forEach((key, value) {
      // Skip null, empty, or system values
      if (value == null ||
          value.toString().isEmpty ||
          (value is List && value.isEmpty)) {
        return;
      }

      // Skip system/internal fields that shouldn't be displayed
      final systemFields = {
        // Document identifiers
        'productId',
        'orderId',
        'buyerId',
        'sellerId',

        // Timestamps
        'timestamp',
        'addedAt',
        'updatedAt',

        // Images (not user selections)
        'selectedColorImage',
        'productImage',

        // Pricing fields (calculated by cart/system)
        'price',
        'finalPrice',
        'calculatedUnitPrice',
        'calculatedTotal',
        'unitPrice',
        'totalPrice',
        'currency',

        // Bundle/sale system fields
        'isBundleItem',
        'bundleInfo',
        'salePreferences',
        'isBundle',
        'bundleId',
        'mainProductPrice',
        'bundlePrice',

        // Seller info (displayed elsewhere)
        'sellerName',
        'isShop',
        'shopId',

        // Product metadata (not user choices)
        'productName',
        'brandModel',
        'brand',
        'category',
        'subcategory',
        'subsubcategory',
        'condition',
        'averageRating',
        'productAverageRating',
        'reviewCount',
        'productReviewCount',
        'clothingType',
        'clothingTypes',
        'pantFabricTypes',
        'pantFabricType',
        'clothingFit',
        'gender',

        // Order/shipping status
        'shipmentStatus',
        'deliveryOption',
        'needsProductReview',
        'needsSellerReview',
        'needsAnyReview',

        // System quantities (quantity handled separately above)
        'quantity',
        'availableStock',
        'maxQuantityAllowed',
        'ourComission',
        'sellerContactNo',
        'showSellerHeader',
      };

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
        final currentColor = colorPalette[colorIndex % colorPalette.length];
        colorIndex++;

        attributeChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: currentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$localizedKey: ',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: currentColor,
                    ),
                  ),
                  TextSpan(
                    text: localizedValue,
                    style: TextStyle(
                      fontSize: 9,
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
        final fallbackColor = colorPalette[colorIndex % colorPalette.length];
        colorIndex++;

        attributeChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: fallbackColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$key: $value',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: fallbackColor,
              ),
            ),
          ),
        );
      }
    });

    return Row(
      children: [
        // Attributes
        if (attributeChips.isNotEmpty)
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: attributeChips,
            ),
          ),

        // Add spacing if both attributes and date exist
        if (attributeChips.isNotEmpty && timestamp != null)
          const SizedBox(width: 8),

        // Date
        if (timestamp != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              DateFormat('dd/MM/yy').format(timestamp.toDate()),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactStatusChip(
      String status, AppLocalizations l10n, bool isDark) {
    Color backgroundColor;
    Color textColor;
    String displayText;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor =
            isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        textColor = isDark ? const Color(0xFFFCD34D) : const Color(0xFFD69E2E);
        displayText = l10n.shipmentPending;
        icon = Icons.schedule;
        break;
      case 'collecting':
      case 'assigned':
        backgroundColor =
            isDark ? const Color(0xFF7C2D12) : const Color(0xFFFFEDD5);
        textColor = isDark ? const Color(0xFFFDBA74) : Colors.orange;
        displayText = l10n.shipmentCollecting;
        icon = Icons.person_pin_circle;
        break;
      case 'in_transit':
      case 'gathered':
        backgroundColor =
            isDark ? const Color(0xFF1E3A5F) : const Color(0xFFDBEAFE);
        textColor = isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6);
        displayText = l10n.shipmentInTransit;
        icon = Icons.local_shipping;
        break;
      case 'at_warehouse':
        backgroundColor =
            isDark ? const Color(0xFF4C1D95) : const Color(0xFFEDE9FE);
        textColor = isDark ? const Color(0xFFC4B5FD) : Colors.purple;
        displayText = l10n.shipmentAtWarehouse;
        icon = Icons.warehouse;
        break;
      case 'out_for_delivery':
        backgroundColor =
            isDark ? const Color(0xFF312E81) : const Color(0xFFE0E7FF);
        textColor = isDark ? const Color(0xFFA5B4FC) : Colors.indigo;
        displayText = l10n.shipmentOutForDelivery;
        icon = Icons.delivery_dining;
        break;
      case 'shipped':
        backgroundColor =
            isDark ? const Color(0xFF1E3A5F) : const Color(0xFFDBEAFE);
        textColor = isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6);
        displayText = l10n.shipped;
        icon = Icons.local_shipping;
        break;
      case 'delivered':
        backgroundColor =
            isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
        textColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF10B981);
        displayText = l10n.shipmentDelivered;
        icon = Icons.check_circle;
        break;
      case 'cancelled':
      case 'failed':
        backgroundColor =
            isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        textColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFEF4444);
        displayText = status.toLowerCase() == 'failed'
            ? l10n.shipmentFailed
            : l10n.cancelled;
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

  Widget _buildCompactActionButton(BuildContext context,
      Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
    final status = _getShipmentStatusFromItem(item);

    // Only show ship button if pending
    if (status == 'pending') {
      return ElevatedButton(
        onPressed: () => _showModernShipmentDialog(context, item, l10n, isDark),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
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
          l10n.ship,
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
        status == 'delivered' ? l10n.shipmentDelivered : l10n.inProgress,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
    );
  }

  void _showModernShipmentDialog(BuildContext context,
      Map<String, dynamic> item, AppLocalizations l10n, bool isDark) {
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
              color:
                  isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    size: 24,
                    color: Color(0xFF6366F1),
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
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
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
                          _updateShipmentStatus(
                              item['orderId'], item['productId']);
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
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
      // Find the specific item document for shop products
      final itemsQuery = await _firestore
          .collection('orders')
          .doc(orderId)
          .collection('items')
          .where('productId', isEqualTo: productId)
          .where('shopId', isEqualTo: widget.shopId)
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
