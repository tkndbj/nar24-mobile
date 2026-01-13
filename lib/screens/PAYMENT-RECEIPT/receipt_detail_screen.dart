// lib/screens/receipt_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../models/receipt.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../utils/attribute_localization_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final Receipt receipt;

  const ReceiptDetailScreen({Key? key, required this.receipt})
      : super(key: key);

  @override
  _ReceiptDetailScreenState createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  Map<String, dynamic>? _orderData;
  List<Map<String, dynamic>> _orderItems = [];
  bool _isLoading = true;
  final TextEditingController _emailController = TextEditingController();
  bool _isSendingEmail = false;

  String? _deliveryQRUrl;
  bool _isQRLoading = false;
  bool _isSharingQR = false;

  @override
  void initState() {
    super.initState();
    _fetchOrderDetails();
    _loadUserEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          _emailController.text = userData?['email'] ?? user.email ?? '';
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading user email: $e');
      }
    }
  }

  void _showQRCodeModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    // Check QR generation status
    final qrStatus = _orderData?['qrGenerationStatus'];
    final hasQR = _deliveryQRUrl != null && _deliveryQRUrl!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Modal handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[600] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Icon and title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.pink],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              FeatherIcons.grid,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.deliveryQRCode ?? 'Delivery QR Code',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.showThisToDelivery ??
                                      'Show this to the delivery person',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Order info badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.withOpacity(0.1),
                              Colors.pink.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              FeatherIcons.package,
                              size: 16,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${l10n.orders ?? "Order"} #${widget.receipt.orderId.substring(0, 8).toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // QR Code Display
                      if (hasQR) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _deliveryQRUrl!,
                              width: 250,
                              height: 250,
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  width: 250,
                                  height: 250,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                              : null,
                                      color: Colors.orange,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return SizedBox(
                                  width: 250,
                                  height: 250,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        FeatherIcons.alertCircle,
                                        size: 48,
                                        color: Colors.red[300],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        l10n.failedToLoadQR ??
                                            'Failed to load QR code',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 12),
                                      TextButton.icon(
                                        onPressed: () {
                                          setModalState(() {});
                                        },
                                        icon: const Icon(FeatherIcons.refreshCw,
                                            size: 16),
                                        label: Text(l10n.retry ?? 'Retry'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Share button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: _isSharingQR
                                  ? null
                                  : const LinearGradient(
                                      colors: [Colors.orange, Colors.pink],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              color: _isSharingQR ? Colors.grey : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _isSharingQR
                                    ? null
                                    : () async {
                                        setModalState(() {
                                          _isSharingQR = true;
                                        });

                                        await _shareQRCode();

                                        setModalState(() {
                                          _isSharingQR = false;
                                        });
                                      },
                                child: Center(
                                  child: _isSharingQR
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              FeatherIcons.share2,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              l10n.shareQRCode ??
                                                  'Share QR Code',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // QR not available state
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                qrStatus == 'processing'
                                    ? FeatherIcons.loader
                                    : qrStatus == 'failed'
                                        ? FeatherIcons.alertCircle
                                        : FeatherIcons.clock,
                                size: 64,
                                color: qrStatus == 'failed'
                                    ? Colors.red[400]
                                    : Colors.orange,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                qrStatus == 'processing'
                                    ? (l10n.qrGenerating ??
                                        'Generating QR Code...')
                                    : qrStatus == 'failed'
                                        ? (l10n.qrGenerationFailed ??
                                            'QR generation failed')
                                        : (l10n.qrNotReady ??
                                            'QR Code not ready yet'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                qrStatus == 'processing'
                                    ? (l10n.pleaseWaitQR ??
                                        'Please wait a moment...')
                                    : qrStatus == 'failed'
                                        ? (l10n.tapToRetryQR ?? 'Tap to retry')
                                        : (l10n.qrWillBeReady ??
                                            'It will be ready shortly'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (qrStatus == 'failed') ...[
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: _isQRLoading
                                      ? null
                                      : () async {
                                          setModalState(() {
                                            _isQRLoading = true;
                                          });

                                          await _retryQRGeneration();

                                          setModalState(() {
                                            _isQRLoading = false;
                                          });

                                          Navigator.pop(context);
                                        },
                                  icon: _isQRLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.orange,
                                          ),
                                        )
                                      : const Icon(FeatherIcons.refreshCw,
                                          size: 16),
                                  label: Text(_isQRLoading
                                      ? (l10n.retrying ?? 'Retrying...')
                                      : (l10n.retry ?? 'Retry')),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Close button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context),
                              child: Center(
                                child: Text(
                                  l10n.close ?? 'Close',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareQRCode() async {
    if (_deliveryQRUrl == null || _deliveryQRUrl!.isEmpty) return;

    try {
      final l10n = AppLocalizations.of(context);

      // Download the QR image
      final response = await http.get(Uri.parse(_deliveryQRUrl!));

      if (response.statusCode == 200) {
        // Save to temp directory
        final tempDir = await getTemporaryDirectory();
        final file = File(
            '${tempDir.path}/qr_order_${widget.receipt.orderId.substring(0, 8)}.png');
        await file.writeAsBytes(response.bodyBytes);

        // Share the file
        await Share.shareXFiles(
          [XFile(file.path)],
          text:
              '${l10n.orderQRCode ?? "Order QR Code"} #${widget.receipt.orderId.substring(0, 8).toUpperCase()}',
        );
      } else {
        throw Exception('Failed to download QR code');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sharing QR code: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).failedToShareQR ??
                'Failed to share QR code'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _retryQRGeneration() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('retryQRGeneration');

      final result = await callable.call({
        'orderId': widget.receipt.orderId,
      });

      if (result.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).qrRetryInitiated ??
                  'QR generation retry initiated'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Refresh order data after a short delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              _fetchOrderDetails();
            }
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error retrying QR generation: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).failedToRetryQR ??
                'Failed to retry QR generation'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.receipt.orderId)
          .get();

      if (orderDoc.exists) {
        final itemsSnapshot = await FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.receipt.orderId)
            .collection('items')
            .get();

        // ✅ ADD: Extract QR URL
        final orderData = orderDoc.data();
        String? qrUrl;
        if (orderData != null && orderData['deliveryQR'] != null) {
          qrUrl = orderData['deliveryQR']['url'] as String?;
        }

        setState(() {
          _orderData = orderData;
          _orderItems = itemsSnapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
          _deliveryQRUrl = qrUrl; // ✅ ADD THIS
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching order details: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showEmailModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Modal handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[600] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Icon and title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.pink],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              FeatherIcons.mail,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.sendReceiptByEmail ??
                                      'Send Receipt by Email',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.receiptWillBeSentToEmail ??
                                      'Your receipt will be sent to the email below',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Email input field
                      Text(
                        l10n.emailAddress ?? 'Email Address',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                l10n.enterEmailAddress ?? 'Enter email address',
                            hintStyle: TextStyle(
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[400],
                            ),
                            prefixIcon: Icon(
                              FeatherIcons.mail,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                              size: 18,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Receipt preview
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.withOpacity(0.1),
                              Colors.pink.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
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
                                FeatherIcons.fileText,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${l10n.receipt ?? "Receipt"} #${widget.receipt.receiptId.substring(0, 8).toUpperCase()}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${l10n.orders ?? "Order"} #${widget.receipt.orderId.substring(0, 8).toUpperCase()}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${widget.receipt.totalPrice.toStringAsFixed(0)} ${widget.receipt.currency}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[600]!
                                      : Colors.grey[300]!,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _isSendingEmail
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: Center(
                                    child: Text(
                                      l10n.cancel ?? 'Cancel',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[300]
                                            : Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: _isSendingEmail
                                    ? null
                                    : const LinearGradient(
                                        colors: [Colors.orange, Colors.pink],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: _isSendingEmail ? Colors.grey : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _isSendingEmail
                                      ? null
                                      : () async {
                                          if (_emailController.text.isEmpty) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(l10n
                                                        .pleaseEnterEmail ??
                                                    'Please enter an email address'),
                                                backgroundColor: Colors.orange,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                            return;
                                          }

                                          setModalState(() {
                                            _isSendingEmail = true;
                                          });

                                          final success =
                                              await _sendReceiptByEmail(
                                                  _emailController.text);

                                          setModalState(() {
                                            _isSendingEmail = false;
                                          });

                                          if (success) {
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(l10n
                                                        .receiptSentSuccessfully ??
                                                    'Receipt sent successfully!'),
                                                backgroundColor: Colors.green,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                  child: Center(
                                    child: _isSendingEmail
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                FeatherIcons.send,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                l10n.sendEmail ?? 'Send Email',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _sendReceiptByEmail(String email) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('sendReceiptEmail');

      final result = await callable.call({
        'receiptId': widget.receipt.receiptId,
        'orderId': widget.receipt.orderId,
        'email': email,
      });

      if (result.data['success'] == true) {
        return true;
      } else {
        throw Exception('Failed to send email');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending receipt email: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send email. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  void _copyOrderId() {
    Clipboard.setData(ClipboardData(text: widget.receipt.orderId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order ID copied to clipboard'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
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
            l10n.receiptDetails,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(
                FeatherIcons.grid,
                color: theme.textTheme.bodyMedium?.color,
              ),
              onPressed: _showQRCodeModal,
            ),
            IconButton(
              icon: Icon(
                FeatherIcons.mail,
                color: theme.textTheme.bodyMedium?.color,
              ),
              onPressed: _showEmailModal,
              tooltip: l10n.sendByEmail ?? 'Send by Email',
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : SingleChildScrollView(
                  child: Column(
                  children: [
                    _buildReceiptHeader(context, isDark, l10n, theme),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _buildOrderInfo(context, isDark, l10n, theme),
                          const SizedBox(height: 16),
                          if (_orderData != null &&
                              _orderData!['address'] != null)
                            _buildDeliveryInfo(context, isDark, l10n, theme),
                          if (_orderData != null &&
                              _orderData!['address'] != null)
                            const SizedBox(height: 16),
                          if (_orderItems.isNotEmpty)
                            _buildItemsList(context, isDark, l10n, theme),
                          if (_orderItems.isNotEmpty)
                            const SizedBox(height: 16),
                          _buildPriceSummary(context, isDark, l10n, theme),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
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
              FeatherIcons.checkCircle,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.receiptDetails,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyMedium?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(widget.receipt.timestamp),
            style: TextStyle(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getLocalizedDeliveryOption(
      String option, AppLocalizations l10n, ThemeData theme) {
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

  Widget _buildOrderInfo(BuildContext context, bool isDark,
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
                    colors: [Colors.orange, Colors.pink],
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
                l10n.orderInformation ?? 'Order Information',
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
            '#${widget.receipt.orderId.substring(0, 8).toUpperCase()}',
            isDark,
            theme,
            showCopy: true,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.withOpacity(0.2), height: 1),
          const SizedBox(height: 8),
          _buildInfoRow(
            l10n.receiptNumber,
            '#${widget.receipt.receiptId.substring(0, 8).toUpperCase()}',
            isDark,
            theme,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.withOpacity(0.2), height: 1),
          const SizedBox(height: 8),
          _buildInfoRow(
            l10n.paymentMethod,
            widget.receipt.paymentMethod,
            isDark,
            theme,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.withOpacity(0.2), height: 1),
          const SizedBox(height: 8),
          _buildInfoRow(
            l10n.delivery ?? 'Delivery',
            _getLocalizedDeliveryOption(
                widget.receipt.deliveryOption ?? '', l10n, theme),
            isDark,
            valueColor: _getDeliveryColor(widget.receipt.deliveryOption ?? ''),
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryInfo(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    final address = _orderData!['address'] as Map<String, dynamic>;

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
                  FeatherIcons.mapPin,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.deliveryAddress ?? 'Delivery Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            address['addressLine1'] ?? '',
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
            ),
          ),
          if (address['addressLine2'] != null &&
              address['addressLine2'].isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                address['addressLine2'],
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${address['city'] ?? ''} • ${address['phoneNumber'] ?? ''}',
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    Map<String, List<Map<String, dynamic>>> groupedItems = {};
    for (var item in _orderItems) {
      String sellerId = item['sellerId'] ?? 'unknown';
      if (!groupedItems.containsKey(sellerId)) {
        groupedItems[sellerId] = [];
      }
      groupedItems[sellerId]!.add(item);
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
                  FeatherIcons.shoppingBag,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.purchasedItems ?? 'Purchased Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...groupedItems.entries.map((entry) {
            final sellerItems = entry.value;
            final sellerName =
                sellerItems.first['sellerName'] ?? 'Unknown Seller';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.withOpacity(0.2),
                        Colors.pink.withOpacity(0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FeatherIcons.user,
                        size: 12,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sellerName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...sellerItems
                    .map((item) => _buildItemRow(item, isDark, l10n, theme)),
                if (entry.key != groupedItems.keys.last)
                  const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> item, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    final theme = Theme.of(context);
    final attributes = item['selectedAttributes'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.2),
                  Colors.pink.withOpacity(0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '${item['quantity']}x',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['productName'] ?? 'Unknown Product',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                if (attributes != null && attributes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatLocalizedAttributes(attributes, l10n, theme),
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item['price']} ${item['currency'] ?? 'TL'}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLocalizedAttributes(
      Map<String, dynamic> attributes, AppLocalizations l10n, ThemeData theme) {
    final List<String> localizedAttributes = [];

    attributes.entries.forEach((entry) {
      final key = entry.key;
      final value = entry.value;

      if (value == null ||
          value.toString().isEmpty ||
          (value is List && value.isEmpty)) {
        return;
      }

      final systemFields = {
        'productId',
        'orderId',
        'buyerId',
        'sellerId',
        'timestamp',
        'addedAt',
        'updatedAt',
        'selectedColorImage',
        'productImage',
        'price',
        'finalPrice',
        'calculatedUnitPrice',
        'calculatedTotal',
        'unitPrice',
        'totalPrice',
        'currency',
        'isBundleItem',
        'bundleInfo',
        'salePreferences',
        'isBundle',
        'bundleId',
        'mainProductPrice',
        'bundlePrice',
        'sellerName',
        'isShop',
        'shopId',
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
        'clothingFit',
        'gender',
        'shipmentStatus',
        'deliveryOption',
        'needsProductReview',
        'needsSellerReview',
        'needsAnyReview',
        'quantity',
        'availableStock',
        'maxQuantityAllowed',
        'ourComission',
        'sellerContactNo',
        'showSellerHeader',
        'clothingTypes',
        'pantFabricTypes',
        'pantFabricType',
      };

      if (systemFields.contains(key)) {
        return;
      }

      String localizedKey;
      String localizedValue;

      if (key == 'selectedColor') {
        localizedKey = l10n.color ?? 'Color';
        localizedValue = AttributeLocalizationUtils.localizeColorName(
            value.toString(), l10n);
      } else {
        localizedKey =
            AttributeLocalizationUtils.getLocalizedAttributeTitle(key, l10n);
        localizedValue = AttributeLocalizationUtils.getLocalizedAttributeValue(
            key, value, l10n);
      }

      localizedAttributes.add('$localizedKey: $localizedValue');
    });

    return localizedAttributes.join(', ');
  }

  Widget _buildPriceSummary(BuildContext context, bool isDark,
      AppLocalizations l10n, ThemeData theme) {
    final theme = Theme.of(context);
    final subtotal = widget.receipt.itemsSubtotal;
    final deliveryPrice = widget.receipt.deliveryPrice;
    final grandTotal = widget.receipt.totalPrice;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.subtotal ?? 'Subtotal',
                style: TextStyle(
                  fontSize: 15,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
              Text(
                '${subtotal.toStringAsFixed(0)} ${widget.receipt.currency}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.delivery ?? 'Delivery',
                style: TextStyle(
                  fontSize: 15,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
              Text(
                deliveryPrice == 0
                    ? l10n.free ?? 'Free'
                    : '${deliveryPrice.toStringAsFixed(0)} ${widget.receipt.currency}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: deliveryPrice == 0
                      ? Colors.green
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
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
                  Colors.green.withOpacity(0.1),
                  Colors.green.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.green.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.total ?? 'Total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                Text(
                  '${grandTotal.toStringAsFixed(0)} ${widget.receipt.currency}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark,
    ThemeData theme, // Add this parameter
    {
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

  Color _getDeliveryColor(String deliveryOption) {
    switch (deliveryOption) {
      case 'express':
        return Colors.orange;
      case 'gelal':
        return Colors.blue;
      case 'normal':
      default:
        return Colors.green;
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
