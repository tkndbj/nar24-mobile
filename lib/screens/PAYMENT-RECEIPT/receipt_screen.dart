// lib/screens/receipts/receipt_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/receipt.dart';
import 'receipt_detail_screen.dart';
import 'food_receipt_detail_screen.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Food Receipt model (local)
// ─────────────────────────────────────────────────────────────────────────────

class FoodReceipt {
  final String id;
  final String orderId;
  final String receiptId;
  final double totalPrice;
  final String currency;
  final DateTime timestamp;
  final String paymentMethod;
  final bool isPaid;
  final String deliveryType;
  final String restaurantName;
  final String? filePath;
  final String? downloadUrl;

  bool get isPickup => deliveryType == 'pickup';

  const FoodReceipt({
    required this.id,
    required this.orderId,
    required this.receiptId,
    required this.totalPrice,
    required this.currency,
    required this.timestamp,
    required this.paymentMethod,
    required this.isPaid,
    required this.deliveryType,
    required this.restaurantName,
    this.filePath,
    this.downloadUrl,
  });

  factory FoodReceipt.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['timestamp'];
    DateTime t;
    if (ts is Timestamp) {
      t = ts.toDate();
    } else if (ts is String) {
      t = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      t = DateTime.now();
    }
    return FoodReceipt(
      id: doc.id,
      orderId: d['orderId'] as String? ?? '',
      receiptId: d['receiptId'] as String? ?? '',
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'TL',
      timestamp: t,
      paymentMethod: d['paymentMethod'] as String? ?? '',
      isPaid: d['isPaid'] as bool? ?? false,
      deliveryType: d['deliveryType'] as String? ?? 'delivery',
      restaurantName: d['restaurantName'] as String? ?? '',
      filePath: d['filePath'] as String?,
      downloadUrl: d['downloadUrl'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({Key? key}) : super(key: key);

  @override
  _ReceiptScreenState createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TabController _tabController;
  int _activeTab = 0;

  // ── Product receipts (original, untouched) ──────────────────────────────
  final ScrollController _scrollController = ScrollController();
  List<Receipt> _receipts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  static const int _limit = 20;
  bool _isInitialLoad = true;

  // ── Food receipts ───────────────────────────────────────────────────────
  final ScrollController _foodScrollController = ScrollController();
  List<FoodReceipt> _foodReceipts = [];
  bool _isFoodLoading = false;
  bool _hasFoodMore = true;
  DocumentSnapshot? _lastFoodDocument;
  bool _isFoodInitialLoad = true;
  bool _foodFetched = false;

  bool get _shouldPreventPop {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    return extra?['preventPop'] == true;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _activeTab = _tabController.index);
          if (_tabController.index == 1 && !_foodFetched) {
            _fetchFoodReceipts();
          }
        }
      });
    _fetchReceipts();
    _scrollController.addListener(_scrollListener);
    _foodScrollController.addListener(_foodScrollListener);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _foodScrollController.dispose();
    super.dispose();
  }

  // ── Scroll listeners ────────────────────────────────────────────────────

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) _loadMoreReceipts();
    }
  }

  void _foodScrollListener() {
    if (_foodScrollController.position.pixels >=
        _foodScrollController.position.maxScrollExtent - 200) {
      if (!_isFoodLoading && _hasFoodMore) _loadMoreFoodReceipts();
    }
  }

  // ── Product receipts (original, untouched) ──────────────────────────────

  Future<void> _fetchReceipts() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('receipts')
            .orderBy('timestamp', descending: true)
            .limit(_limit)
            .get();
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
          setState(() {
            _receipts =
                snapshot.docs.map((d) => Receipt.fromDocument(d)).toList();
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
        debugPrint('Error fetching receipts: $e');
        setState(() => _isInitialLoad = false);
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadMoreReceipts() async {
    if (_isLoading || !_hasMore || _lastDocument == null) return;
    setState(() => _isLoading = true);
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('receipts')
            .orderBy('timestamp', descending: true)
            .startAfterDocument(_lastDocument!)
            .limit(_limit)
            .get();
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
          setState(() {
            _receipts.addAll(
                snapshot.docs.map((d) => Receipt.fromDocument(d)).toList());
            _hasMore = snapshot.docs.length >= _limit;
          });
        } else {
          setState(() => _hasMore = false);
        }
      } catch (e) {
        debugPrint('Error loading more receipts: $e');
      }
    }
    setState(() => _isLoading = false);
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

  // ── Food receipts ───────────────────────────────────────────────────────

  Future<void> _fetchFoodReceipts({bool reset = true}) async {
    if (_isFoodLoading) return;
    setState(() => _isFoodLoading = true);
    final user = _auth.currentUser;
    if (user != null) {
      try {
        Query<Map<String, dynamic>> q = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('foodReceipts')
            .orderBy('timestamp', descending: true)
            .limit(_limit);
        if (!reset && _lastFoodDocument != null) {
          q = q.startAfterDocument(_lastFoodDocument!);
        }
        final snapshot = await q.get();
        if (snapshot.docs.isNotEmpty) {
          _lastFoodDocument = snapshot.docs.last;
          final items =
              snapshot.docs.map((d) => FoodReceipt.fromDoc(d)).toList();
          setState(() {
            if (reset) {
              _foodReceipts = items;
            } else {
              _foodReceipts.addAll(items);
            }
            _hasFoodMore = snapshot.docs.length >= _limit;
            _isFoodInitialLoad = false;
          });
        } else {
          setState(() {
            _hasFoodMore = false;
            _isFoodInitialLoad = false;
          });
        }
      } catch (e) {
        debugPrint('Error fetching food receipts: $e');
        setState(() => _isFoodInitialLoad = false);
      }
    }
    setState(() {
      _isFoodLoading = false;
      _foodFetched = true;
    });
  }

  Future<void> _loadMoreFoodReceipts() async {
    if (_isFoodLoading || !_hasFoodMore) return;
    await _fetchFoodReceipts(reset: false);
  }

  Future<void> _refreshFoodReceipts() async {
    setState(() {
      _foodReceipts.clear();
      _lastFoodDocument = null;
      _hasFoodMore = true;
      _isFoodInitialLoad = true;
      _foodFetched = false;
    });
    await _fetchFoodReceipts();
  }

  // ── Helpers (original) ──────────────────────────────────────────────────

  Color _getDeliveryColor(String o) {
    switch (o) {
      case 'express':
        return Colors.orange;
      case 'gelal':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  IconData _getDeliveryIcon(String o) {
    switch (o) {
      case 'express':
        return FeatherIcons.zap;
      case 'gelal':
        return FeatherIcons.mapPin;
      default:
        return FeatherIcons.truck;
    }
  }

  String _localizeDeliveryOption(String o, AppLocalizations l10n) {
    switch (o) {
      case 'express':
        return l10n.deliveryOption2;
      case 'gelal':
        return l10n.deliveryOption1;
      default:
        return l10n.deliveryOption3;
    }
  }

  String _localizePaymentMethod(String method, AppLocalizations l10n) {
    switch (method.toLowerCase()) {
      case 'card':
        return l10n.card;
      case 'cash':
        return l10n.cash;
      case 'bank_transfer':
        return l10n.bankTransfer;
      case 'pay_at_door':
        return l10n.payAtDoor;
      default:
        return method;
    }
  }

  String _formatDate(DateTime ts, AppLocalizations l10n) {
    final diff = DateTime.now().difference(ts);
    if (diff.inDays == 0) {
      return '${l10n.today}, ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return l10n.yesterday;
    } else if (diff.inDays < 7) {
      return '${diff.inDays} ${l10n.daysAgo}';
    }
    return '${ts.day}/${ts.month}/${ts.year}';
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
            icon: Icon(FeatherIcons.arrowLeft,
                color: theme.textTheme.bodyMedium?.color),
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
          actions: [
            IconButton(
              icon: Icon(FeatherIcons.refreshCw,
                  size: 18,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6)),
              onPressed:
                  _activeTab == 0 ? _refreshReceipts : _refreshFoodReceipts,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  padding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.orange, Colors.deepOrange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor:
                      isDark ? Colors.grey[400] : Colors.grey[600],
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 12),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: [
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FeatherIcons.shoppingBag, size: 13),
                          const SizedBox(width: 6),
                          Text(l10n.productOrders),
                        ],
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.restaurant_menu_rounded, size: 13),
                          const SizedBox(width: 6),
                          Text(l10n.foodOrders),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: PopScope(
            canPop: !_shouldPreventPop,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _shouldPreventPop) context.go('/');
            },
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProductTab(l10n, isDark),
                _buildFoodTab(l10n, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRODUCT TAB  (original layout, untouched)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProductTab(AppLocalizations l10n, bool isDark) {
    final theme = Theme.of(context);
    return Column(
      children: [
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
                child: const Icon(FeatherIcons.fileText,
                    color: Colors.white, size: 32),
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
                l10n.yourPurchaseReceiptsWillAppearHere,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isInitialLoad
              ? _buildShimmerList()
              : _receipts.isEmpty
                  ? _buildProductEmptyState(l10n, isDark)
                  : RefreshIndicator(
                      onRefresh: _refreshReceipts,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _receipts.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _receipts.length) {
                            return _buildLoadingIndicator();
                          }
                          return _buildReceiptCard(
                              context, _receipts[index], isDark, l10n);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FOOD TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFoodTab(AppLocalizations l10n, bool isDark) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFF97316).withOpacity(0.1),
                const Color(0xFFEF4444).withOpacity(0.1),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.foodOrders,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyMedium?.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.foodReceiptsWillAppearHere,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isFoodInitialLoad
              ? _buildShimmerList()
              : _foodReceipts.isEmpty
                  ? _buildFoodEmptyState(l10n, isDark)
                  : RefreshIndicator(
                      onRefresh: _refreshFoodReceipts,
                      child: ListView.builder(
                        controller: _foodScrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount:
                            _foodReceipts.length + (_hasFoodMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _foodReceipts.length) {
                            return _buildLoadingIndicator();
                          }
                          return _buildFoodReceiptCard(
                              _foodReceipts[index], isDark, l10n);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFoodReceiptCard(
      FoodReceipt receipt, bool isDark, AppLocalizations l10n) {
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FoodReceiptDetailScreen(receiptId: receipt.id),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          const Color(0xFFF97316).withOpacity(0.15),
                          const Color(0xFFEF4444).withOpacity(0.15),
                        ]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.restaurant_menu_rounded,
                          color: Color(0xFFF97316), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.restaurantName.isNotEmpty
                                ? receipt.restaurantName
                                : l10n.foodOrder,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (receipt.isPickup
                                          ? Colors.blue
                                          : Colors.green)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      receipt.isPickup
                                          ? FeatherIcons.mapPin
                                          : FeatherIcons.truck,
                                      size: 11,
                                      color: receipt.isPickup
                                          ? Colors.blue
                                          : Colors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      receipt.isPickup
                                          ? l10n.pickup
                                          : l10n.delivery,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: receipt.isPickup
                                            ? Colors.blue
                                            : Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(FeatherIcons.calendar,
                                  size: 12,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.5)),
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
                                receipt.paymentMethod == 'pay_at_door'
                                    ? FeatherIcons.dollarSign
                                    : FeatherIcons.creditCard,
                                size: 12,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(0.5),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _localizePaymentMethod(
                                    receipt.paymentMethod, l10n),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${receipt.totalPrice.toStringAsFixed(0)} ${receipt.currency}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF97316),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(FeatherIcons.chevronRight,
                              size: 16, color: Color(0xFFF97316)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Paid / pay-at-door strip
              Container(
                decoration: BoxDecoration(
                  color: receipt.isPaid
                      ? (isDark
                          ? Colors.green.withOpacity(0.08)
                          : Colors.green.shade50)
                      : (isDark
                          ? Colors.amber.withOpacity(0.08)
                          : Colors.amber.shade50),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade100,
                    ),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          receipt.isPaid
                              ? Icons.check_circle_outline
                              : Icons.payments_outlined,
                          size: 13,
                          color:
                              receipt.isPaid ? Colors.green : Colors.amber[700],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          receipt.isPaid ? l10n.paid : l10n.payAtDoor,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: receipt.isPaid
                                ? Colors.green
                                : Colors.amber[700],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '#${receipt.orderId.substring(0, receipt.orderId.length.clamp(0, 8)).toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProductEmptyState(AppLocalizations l10n, bool isDark) {
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
                gradient: LinearGradient(colors: [
                  Colors.orange.withOpacity(0.1),
                  Colors.pink.withOpacity(0.1),
                ]),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.orange, Colors.pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: const Icon(FeatherIcons.fileText,
                    size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 32),
            Text(l10n.noReceiptsFound,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyMedium?.color),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(l10n.yourPurchaseReceiptsWillAppearHere,
                style: TextStyle(
                    fontSize: 15,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    height: 1.4),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodEmptyState(AppLocalizations l10n, bool isDark) {
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
                gradient: LinearGradient(colors: [
                  const Color(0xFFF97316).withOpacity(0.1),
                  const Color(0xFFEF4444).withOpacity(0.1),
                ]),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 32),
            Text(l10n.noReceiptsFound,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.bodyMedium?.color),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(l10n.foodReceiptsWillAppearHere,
                style: TextStyle(
                    fontSize: 15,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                    height: 1.4),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _buildShimmerCard());

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildShimmerCard()),
    );
  }

  Widget _buildShimmerCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF1E1C2C) : const Color(0xFFE0E0E0),
      highlightColor:
          isDark ? const Color(0xFF211F31) : const Color(0xFFF5F5F5),
      period: const Duration(milliseconds: 1200),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 8),
                  Container(
                      width: 140,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 6),
                  Container(
                      width: 100,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                    width: 60,
                    height: 14,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Original receipt card — untouched
  Widget _buildReceiptCard(BuildContext context, Receipt receipt, bool isDark,
      AppLocalizations l10n) {
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ReceiptDetailScreen(receipt: receipt)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.orange.withOpacity(0.2),
                      Colors.pink.withOpacity(0.2),
                    ]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(FeatherIcons.fileText,
                      color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${receipt.getReceiptTypeDisplay(l10n)} #${receipt.orderId.substring(0, 8).toUpperCase()}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodyMedium?.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          receipt.isBoostReceipt
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00A86B)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.rocket_launch_rounded,
                                          size: 12, color: Color(0xFF00A86B)),
                                      const SizedBox(width: 4),
                                      Text(
                                          receipt
                                              .getFormattedBoostDuration(l10n),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF00A86B))),
                                    ],
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
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
                                              receipt.deliveryOption ?? '')),
                                      const SizedBox(width: 4),
                                      Text(
                                          _localizeDeliveryOption(
                                              receipt.deliveryOption ?? '',
                                              l10n),
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _getDeliveryColor(
                                                  receipt.deliveryOption ??
                                                      ''))),
                                    ],
                                  ),
                                ),
                          const SizedBox(width: 8),
                          Icon(FeatherIcons.calendar,
                              size: 12,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _formatDate(receipt.timestamp, l10n),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.6)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(FeatherIcons.creditCard,
                              size: 12,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Text(
                              _localizePaymentMethod(
                                  receipt.paymentMethod, l10n),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.6))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${receipt.totalPrice.toStringAsFixed(0)} ${receipt.currency}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Icon(FeatherIcons.chevronRight,
                          size: 16, color: Colors.orange),
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
}
