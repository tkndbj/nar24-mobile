// lib/SELLER-PANEL/seller_panel_receipts_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/receipt.dart';
import '../../screens/SELLER-PANEL/seller_panel_receipt_detail_screen.dart';
import '../../generated/l10n/app_localizations.dart';

class SellerPanelReceiptsScreen extends StatefulWidget {
  final String shopId;

  const SellerPanelReceiptsScreen({
    Key? key,
    required this.shopId,
  }) : super(key: key);

  @override
  _SellerPanelReceiptsScreenState createState() =>
      _SellerPanelReceiptsScreenState();
}

class _SellerPanelReceiptsScreenState extends State<SellerPanelReceiptsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<Receipt> _receipts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  static const int _limit = 20;
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _fetchReceipts();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMoreReceipts();
      }
    }
  }

  Future<void> _fetchReceipts() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('receipts')
          .orderBy('timestamp', descending: true)
          .limit(_limit);

      QuerySnapshot snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        List<Receipt> receipts = snapshot.docs.map((doc) {
          return Receipt.fromDocument(doc);
        }).toList();

        setState(() {
          _receipts = receipts;
          _hasMore = snapshot.docs.length >= _limit;
          _isInitialLoad = false;
        });
      } else {
        setState(() {
          _isInitialLoad = false;
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error fetching shop receipts: $e');
      setState(() {
        _isInitialLoad = false;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadMoreReceipts() async {
    if (_isLoading || !_hasMore || _lastDocument == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('receipts')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_limit);

      QuerySnapshot snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        List<Receipt> newReceipts = snapshot.docs.map((doc) {
          return Receipt.fromDocument(doc);
        }).toList();

        setState(() {
          _receipts.addAll(newReceipts);
          _hasMore = snapshot.docs.length >= _limit;
        });
      } else {
        setState(() {
          _hasMore = false;
        });
      }
    } catch (e) {
      print('Error loading more shop receipts: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _refreshReceipts() async {
    setState(() {
      _receipts.clear();
      _lastDocument = null;
      _hasMore = true;
      _isInitialLoad = true;
    });
    await _fetchReceipts();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              FeatherIcons.arrowLeft,
              color: theme.textTheme.bodyMedium?.color,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            l10n.receipts,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // Header Section
              Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.orange.withOpacity(0.1),
                    Colors.pink.withOpacity(0.1),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.pink],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      FeatherIcons.fileText,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.receipts,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.shopReceipts ?? 'Shop receipts and payment history'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isInitialLoad
                  ? _buildShimmerLoading(isDark)
                  : _receipts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: const Icon(
                                  FeatherIcons.fileText,
                                  size: 64,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                l10n.noReceipts ?? 'No receipts yet',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.noReceiptsDescription ??
                                    'Your shop receipts will appear here',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.6),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshReceipts,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _receipts.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _receipts.length) {
                                return _buildLoadingIndicator();
                              }
                              return _buildReceiptCard(_receipts[index]);
                            },
                          ),
                        ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => SellerPanelReceiptDetailScreen(
        receipt: receipt,
        shopId: widget.shopId,
      ),
    ),
  );
},
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color.fromARGB(255, 37, 35, 54) : theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withOpacity(0.2),
                        Colors.pink.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getReceiptIcon(receipt.receiptType),
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Receipt Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getReceiptTitle(receipt, l10n),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getReceiptTypeColor(receipt.receiptType)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getReceiptIcon(receipt.receiptType),
                                  size: 12,
                                  color: _getReceiptTypeColor(receipt.receiptType),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _localizeReceiptType(receipt.receiptType, l10n),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _getReceiptTypeColor(receipt.receiptType),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            FeatherIcons.calendar,
                            size: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _formatDate(receipt.timestamp, l10n),
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            FeatherIcons.creditCard,
                            size: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _localizePaymentMethod(receipt.paymentMethod, l10n),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Price and Arrow
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${receipt.totalPrice.toStringAsFixed(0)} ${receipt.currency}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        FeatherIcons.chevronRight,
                        size: 16,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    final baseColor =
        isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D4A) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (context, index) => _buildReceiptCardShimmer(isDark),
      ),
    );
  }

  Widget _buildReceiptCardShimmer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1B23) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? const Color(0xFF4A5568).withOpacity(0.1)
                : const Color(0xFFE2E8F0).withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            // Icon placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            // Content placeholder
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  _buildShimmerBox(width: 140, height: 16, isDark: isDark),
                  const SizedBox(height: 10),
                  // Tags row
                  Row(
                    children: [
                      _buildShimmerBox(width: 60, height: 22, isDark: isDark),
                      const SizedBox(width: 8),
                      _buildShimmerBox(width: 80, height: 14, isDark: isDark),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Payment method
                  _buildShimmerBox(width: 70, height: 14, isDark: isDark),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price and arrow placeholder
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildShimmerBox(width: 70, height: 18, isDark: isDark),
                const SizedBox(height: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2D2D3A)
                        : const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required bool isDark,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D4A) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildReceiptCardShimmer(isDark),
      ),
    );
  }

  IconData _getReceiptIcon(String? receiptType) {
    if (receiptType == 'boost') {
      return FeatherIcons.zap;
    }
    return FeatherIcons.fileText;
  }

  Color _getReceiptTypeColor(String? receiptType) {
    if (receiptType == 'boost') {
      return Colors.purple;
    }
    return Colors.orange;
  }

  String _localizeReceiptType(String? receiptType, AppLocalizations l10n) {
    if (receiptType == 'boost') {
      return l10n.boost ?? 'Boost';
    }
    return l10n.orders ?? 'Order';
  }

  String _getReceiptTitle(Receipt receipt, AppLocalizations l10n) {
    if (receipt.receiptType == 'boost') {
      return '${l10n.boost ?? 'Boost'} #${receipt.orderId.substring(0, 8).toUpperCase()}';
    }
    return '${l10n.orders ?? 'Order'} #${receipt.orderId.substring(0, 8).toUpperCase()}';
  }

  String _localizePaymentMethod(String paymentMethod, AppLocalizations l10n) {
    switch (paymentMethod.toLowerCase()) {
      case 'card':
        return l10n.card ?? 'Card';
      case 'cash':
        return l10n.cash ?? 'Cash';
      case 'bank_transfer':
        return l10n.bankTransfer ?? 'Bank Transfer';
      case 'isbank_3d':
        return 'İşbank 3D';
      default:
        return paymentMethod;
    }
  }

  String _formatDate(DateTime timestamp, AppLocalizations l10n) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      final today = l10n.today ?? 'Today';
      return '$today, ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return l10n.yesterday ?? 'Yesterday';
    } else if (difference.inDays < 7) {
      final daysAgo = l10n.daysAgo ?? 'days ago';
      return '${difference.inDays} $daysAgo';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}