// lib/screens/receipt_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/receipt.dart';
import 'receipt_detail_screen.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({Key? key}) : super(key: key);

  @override
  _ReceiptScreenState createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<Receipt> _receipts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  static const int _limit = 20;
  bool _isInitialLoad = true;

  bool get _shouldPreventPop {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    return extra?['preventPop'] == true;
  }

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

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        Query query = _firestore
            .collection('users')
            .doc(user.uid)
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
        print('Error fetching receipts: $e');
        setState(() {
          _isInitialLoad = false;
        });
      }
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

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        Query query = _firestore
            .collection('users')
            .doc(user.uid)
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
        print('Error loading more receipts: $e');
      }
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
            onPressed: () {
              if (_shouldPreventPop) {
                context.go('/');
              } else {
                Navigator.pop(context);
              }
            },
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
          child: PopScope(
            canPop: !_shouldPreventPop,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _shouldPreventPop) {
                context.go('/');
              }
            },
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
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.yourPurchaseReceiptsWillAppearHere ??
                            'Your purchase receipts will appear here',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.textTheme.bodyMedium?.color
                              ?.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Content
                Expanded(
                  child: _isInitialLoad
                      ? _buildReceiptShimmerList()
                      : _receipts.isEmpty
                          ? _buildEmptyState(context, l10n, isDark)
                          : RefreshIndicator(
                              onRefresh: _refreshReceipts,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount:
                                    _receipts.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _receipts.length) {
                                    return _buildLoadingIndicator();
                                  }
                                  return _buildReceiptCard(
                                    context,
                                    _receipts[index],
                                    isDark,
                                    l10n,
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, AppLocalizations l10n, bool isDark) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.1),
                    Colors.pink.withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.pink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FeatherIcons.fileText,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.noReceiptsFound,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.yourPurchaseReceiptsWillAppearHere ??
                  'Your purchase receipts will appear here',
              style: TextStyle(
                fontSize: 15,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(
    BuildContext context,
    Receipt receipt,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReceiptDetailScreen(receipt: receipt),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Receipt Icon Container
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
                  child: const Icon(
                    FeatherIcons.fileText,
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
                              '${receipt.getReceiptTypeDisplay(l10n)} #${receipt.orderId.substring(0, 8).toUpperCase()}',
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
                          receipt.isBoostReceipt
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00A86B)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.rocket_launch_rounded,
                                        size: 12,
                                        color: Color(0xFF00A86B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        receipt.getFormattedBoostDuration(l10n),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF00A86B),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getDeliveryColor(
                                            receipt.deliveryOption ?? '')
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _getDeliveryIcon(
                                            receipt.deliveryOption ?? ''),
                                        size: 12,
                                        color: _getDeliveryColor(
                                            receipt.deliveryOption ?? ''),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _localizeDeliveryOption(
                                            receipt.deliveryOption ?? '', l10n),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _getDeliveryColor(
                                              receipt.deliveryOption ?? ''),
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

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _buildReceiptShimmerCard(),
    );
  }

  Widget _buildReceiptShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildReceiptShimmerCard(),
      ),
    );
  }

  Widget _buildReceiptShimmerCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF1E1C2C) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF211F31) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Icon placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            // Text placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 140,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price placeholder
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 60,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
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

  IconData _getDeliveryIcon(String deliveryOption) {
    switch (deliveryOption) {
      case 'express':
        return FeatherIcons.zap;
      case 'gelal':
        return FeatherIcons.mapPin;
      case 'normal':
      default:
        return FeatherIcons.truck;
    }
  }

  String _localizeDeliveryOption(String deliveryOption, AppLocalizations l10n) {
    switch (deliveryOption) {
      case 'express':
        return l10n.deliveryOption2 ?? 'Express';
      case 'gelal':
        return l10n.deliveryOption1 ?? 'Pick Up';
      case 'normal':
      default:
        return l10n.deliveryOption3 ?? 'Normal';
    }
  }

  String _localizePaymentMethod(String paymentMethod, AppLocalizations l10n) {
    switch (paymentMethod.toLowerCase()) {
      case 'card':
        return l10n.card ?? 'Card';
      case 'cash':
        return l10n.cash ?? 'Cash';
      case 'bank_transfer':
        return l10n.bankTransfer ?? 'Bank Transfer';
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
