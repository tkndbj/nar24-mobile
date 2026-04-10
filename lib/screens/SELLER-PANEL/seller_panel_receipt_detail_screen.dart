// lib/SELLER-PANEL/seller_panel_receipt_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/receipt.dart';
import '../../generated/l10n/app_localizations.dart';

class SellerPanelReceiptDetailScreen extends StatefulWidget {
  final Receipt receipt;
  final String shopId;

  const SellerPanelReceiptDetailScreen({
    Key? key,
    required this.receipt,
    required this.shopId,
  }) : super(key: key);

  @override
  _SellerPanelReceiptDetailScreenState createState() =>
      _SellerPanelReceiptDetailScreenState();
}

class _SellerPanelReceiptDetailScreenState
    extends State<SellerPanelReceiptDetailScreen> {
  Map<String, dynamic>? _boostData;
  List<Map<String, dynamic>> _boostedItems = [];
  bool _isLoading = true;

  bool get _isAd => widget.receipt.receiptType == 'ad';

  @override
  void initState() {
    super.initState();
    if (!_isAd) {
      _fetchBoostDetails();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchBoostDetails() async {
    try {
      final paymentDoc = await FirebaseFirestore.instance
          .collection('pendingBoostPayments')
          .doc(widget.receipt.orderId)
          .get();

      if (paymentDoc.exists) {
        final paymentData = paymentDoc.data();
        setState(() {
          _boostData = paymentData?['boostData'];
          if (_boostData != null && _boostData!['items'] != null) {
            _boostedItems = List<Map<String, dynamic>>.from(
              _boostData!['items'].map((item) => {
                    'itemId': item['itemId'],
                    'collection': item['collection'],
                    'shopId': item['shopId'],
                  }),
            );
          }
          _isLoading = false;
        });

        await _fetchProductDetails();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching boost details: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchProductDetails() async {
    try {
      List<Map<String, dynamic>> updatedItems = [];

      for (var item in _boostedItems) {
        DocumentSnapshot? productDoc;

        if (item['collection'] == 'shop_products') {
          productDoc = await FirebaseFirestore.instance
              .collection('shop_products')
              .doc(item['itemId'])
              .get();
        } else if (item['collection'] == 'products') {
          productDoc = await FirebaseFirestore.instance
              .collection('products')
              .doc(item['itemId'])
              .get();
        }

        if (productDoc != null && productDoc.exists) {
          final productData = productDoc.data() as Map<String, dynamic>;
          updatedItems.add({
            ...item,
            'productName': productData['name'] ??
                productData['productName'] ??
                'Unknown Product',
            'productImage': productData['imageUrls'] != null &&
                    (productData['imageUrls'] as List).isNotEmpty
                ? productData['imageUrls'][0]
                : null,
          });
        } else {
          updatedItems.add({
            ...item,
            'productName': 'Unknown Product',
            'productImage': null,
          });
        }
      }

      setState(() {
        _boostedItems = updatedItems;
      });
    } catch (e) {
      print('Error fetching product details: $e');
    }
  }

  // --- Ad helper methods ---

  String _getAdTypeLabel(String? adType) {
    switch (adType) {
      case 'topBanner':
        return 'Top Banner';
      case 'thinBanner':
        return 'Thin Banner';
      case 'marketBanner':
        return 'Market Banner';
      default:
        return adType ?? 'Banner';
    }
  }

  String _getAdDurationLabel(String? duration, AppLocalizations l10n) {
    switch (duration) {
      case 'oneWeek':
        return l10n.oneWeek;
      case 'twoWeeks':
        return l10n.twoWeeks;
      case 'oneMonth':
        return l10n.oneMonth;
      default:
        return duration ?? '';
    }
  }

  Future<void> _downloadPdf() async {
    final path = widget.receipt.filePath;
    String? url;
    if (path != null && path.isNotEmpty) {
      try {
        url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      } catch (_) {}
    }
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).receiptPdfNotAvailable),
          ),
        );
      }
    }
  }

  void _copyOrderId() {
    Clipboard.setData(ClipboardData(text: widget.receipt.orderId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              FeatherIcons.copy,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context).orderIdCopied ??
                  'Order ID copied to clipboard',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: isDark
            ? const Color.fromARGB(255, 18, 18, 18)
            : const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: isDark
              ? const Color.fromARGB(255, 18, 18, 18)
              : const Color(0xFFF8F9FA),
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              FeatherIcons.arrowLeft,
              color: theme.textTheme.bodyMedium?.color,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            l10n.receiptDetails ?? 'Receipt Details',
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(FeatherIcons.download),
              onPressed: _downloadPdf,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildReceiptHeader(context, isDark, l10n, theme),
                      const SizedBox(height: 16),
                      _buildInfoCard(context, isDark, l10n, theme),
                      const SizedBox(height: 16),
                      _buildBoostedItemsList(context, isDark, l10n, theme),
                      const SizedBox(height: 16),
                      _buildPriceSummary(context, isDark, l10n, theme),
                      const SizedBox(height: 16),
                      _buildPaymentInfo(context, isDark, l10n, theme),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildReceiptHeader(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isAd
              ? [Colors.orange, Colors.deepOrange]
              : [Colors.purple, Colors.deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(
              _isAd ? Icons.campaign_rounded : FeatherIcons.zap,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isAd ? (l10n.adReceipt) : (l10n.boostReceipt ?? 'Boost Receipt'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '#${widget.receipt.orderId.substring(0, 8).toUpperCase()}',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  FeatherIcons.calendar,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(widget.receipt.timestamp),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isAd
                        ? [Colors.orange, Colors.deepOrange]
                        : [Colors.purple, Colors.deepPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FeatherIcons.info,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isAd
                    ? (l10n.adInformation)
                    : (l10n.boostInformation ?? 'Boost Information'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            l10n.orderNumber ?? 'Order Number',
            '#${widget.receipt.orderId.substring(0, 12).toUpperCase()}',
            isDark,
            theme,
            showCopy: true,
          ),
          const SizedBox(height: 12),
          if (_isAd) ...[
            _buildInfoRow(
              l10n.adType,
              _getAdTypeLabel(widget.receipt.adType),
              isDark,
              theme,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              l10n.duration ?? 'Duration',
              _getAdDurationLabel(widget.receipt.adDuration, l10n),
              isDark,
              theme,
            ),
            if (widget.receipt.itemsSubtotal != null &&
                widget.receipt.itemsSubtotal! > 0) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                l10n.subtotal,
                '${widget.receipt.itemsSubtotal!.toStringAsFixed(0)} ${widget.receipt.currency}',
                isDark,
                theme,
              ),
            ],
            if (widget.receipt.taxAmount != null &&
                widget.receipt.taxAmount! > 0) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                l10n.tax,
                '${widget.receipt.taxAmount!.toStringAsFixed(0)} ${widget.receipt.currency}',
                isDark,
                theme,
              ),
            ],
          ] else ...[
            _buildInfoRow(
              l10n.boostDuration ?? 'Boost Duration',
              '${widget.receipt.boostDuration ?? 0} ${l10n.minutes ?? 'minutes'}',
              isDark,
              theme,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              l10n.boostedItems ?? 'Boosted Items',
              '${widget.receipt.itemCount ?? _boostedItems.length} ${l10n.items ?? 'items'}',
              isDark,
              theme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoostedItemsList(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    if (_isAd || _boostedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.pink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FeatherIcons.package,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.boostedProducts ?? 'Boosted Products',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _boostedItems.length,
            separatorBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                color: Colors.grey.withOpacity(0.2),
                height: 1,
              ),
            ),
            itemBuilder: (context, index) {
              final item = _boostedItems[index];
              final boostDuration = widget.receipt.boostDuration ?? 0;
              final unitPrice = 1.0;
              final totalPrice = boostDuration * unitPrice;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image or icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      image: item['productImage'] != null
                          ? DecorationImage(
                              image: NetworkImage(item['productImage']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: item['productImage'] == null
                        ? Icon(
                            FeatherIcons.box,
                            color: Colors.grey[400],
                            size: 24,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Product details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['productName'] ?? 'Unknown Product',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.duration ?? 'Duration'}: $boostDuration ${l10n.minutes ?? 'min'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Price
                  Text(
                    '${totalPrice.toStringAsFixed(0)} ${widget.receipt.currency}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummary(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    final total = widget.receipt.totalPrice;
    final accentColor = _isAd ? Colors.orange : Colors.purple;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.pink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FeatherIcons.dollarSign,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.priceSummary ?? 'Price Summary',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: Colors.grey.withOpacity(0.2),
              height: 1,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.1),
                  accentColor.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.totalPaid ?? 'Total Paid',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(0)} ${widget.receipt.currency}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.blue, Colors.cyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  FeatherIcons.creditCard,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.paymentInformation ?? 'Payment Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            l10n.paymentMethod ?? 'Payment Method',
            _localizePaymentMethod(widget.receipt.paymentMethod, l10n),
            isDark,
            theme,
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            l10n.paymentStatus ?? 'Payment Status',
            l10n.paid ?? 'Paid',
            isDark,
            theme,
            valueColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark,
    ThemeData theme, {
    bool showCopy = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.textTheme.bodyMedium?.color,
              ),
            ),
            if (showCopy) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _copyOrderId,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    FeatherIcons.copy,
                    size: 14,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
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

  String _formatDate(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/'
        '${timestamp.month.toString().padLeft(2, '0')}/'
        '${timestamp.year} at '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
