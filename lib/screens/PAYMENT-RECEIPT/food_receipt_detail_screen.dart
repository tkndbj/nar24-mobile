// lib/screens/receipts/food_receipt_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../utils/food_localization.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local models
// ─────────────────────────────────────────────────────────────────────────────

class _FoodReceiptDetail {
  final String id;
  final String orderId;
  final String receiptId;
  final double totalPrice;
  final double subtotal;
  final double deliveryFee;
  final String currency;
  final DateTime timestamp;
  final String paymentMethod;
  final bool isPaid;
  final String deliveryType;
  final String restaurantName;
  final String restaurantId;
  final String buyerName;
  final _DeliveryAddress? deliveryAddress;
  final String? filePath;
  final String? downloadUrl;

  bool get isPickup => deliveryType == 'pickup';

  const _FoodReceiptDetail({
    required this.id,
    required this.orderId,
    required this.receiptId,
    required this.totalPrice,
    required this.subtotal,
    required this.deliveryFee,
    required this.currency,
    required this.timestamp,
    required this.paymentMethod,
    required this.isPaid,
    required this.deliveryType,
    required this.restaurantName,
    required this.restaurantId,
    required this.buyerName,
    this.deliveryAddress,
    this.filePath,
    this.downloadUrl,
  });

  factory _FoodReceiptDetail.fromDoc(DocumentSnapshot doc) {
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
    final rawAddr = d['deliveryAddress'];
    return _FoodReceiptDetail(
      id: doc.id,
      orderId: d['orderId'] as String? ?? '',
      receiptId: d['receiptId'] as String? ?? '',
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      subtotal: (d['subtotal'] as num?)?.toDouble() ??
          (d['totalPrice'] as num?)?.toDouble() ??
          0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'TL',
      timestamp: t,
      paymentMethod: d['paymentMethod'] as String? ?? '',
      isPaid: d['isPaid'] as bool? ?? false,
      deliveryType: d['deliveryType'] as String? ?? 'delivery',
      restaurantName: d['restaurantName'] as String? ?? '',
      restaurantId: d['restaurantId'] as String? ?? '',
      buyerName: d['buyerName'] as String? ?? '',
      deliveryAddress: rawAddr is Map<String, dynamic>
          ? _DeliveryAddress.fromMap(rawAddr)
          : null,
      filePath: d['filePath'] as String?,
      downloadUrl: d['downloadUrl'] as String?,
    );
  }
}

class _DeliveryAddress {
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String? phoneNumber;

  const _DeliveryAddress({
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    this.phoneNumber,
  });

  factory _DeliveryAddress.fromMap(Map<String, dynamic> m) => _DeliveryAddress(
        addressLine1: m['addressLine1'] as String? ?? '',
        addressLine2: m['addressLine2'] as String?,
        city: m['city'] as String? ?? '',
        phoneNumber: m['phoneNumber'] as String?,
      );
}

class _FoodOrderItem {
  final String foodId;
  final String name;
  final double price;
  final int quantity;
  final List<_Extra> extras;
  final String? specialNotes;
  final double? itemTotal;

  const _FoodOrderItem({
    required this.foodId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.extras,
    this.specialNotes,
    this.itemTotal,
  });

  factory _FoodOrderItem.fromMap(Map<String, dynamic> m) {
    final rawExtras = m['extras'];
    final extras = rawExtras is List
        ? rawExtras
            .whereType<Map<String, dynamic>>()
            .map(_Extra.fromMap)
            .toList()
        : <_Extra>[];
    return _FoodOrderItem(
      foodId: m['foodId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      price: (m['price'] as num?)?.toDouble() ?? 0,
      quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      extras: extras,
      specialNotes: m['specialNotes'] as String?,
      itemTotal: (m['itemTotal'] as num?)?.toDouble(),
    );
  }

  double get effectiveUnit {
    final extrasTotal =
        extras.fold<double>(0, (s, e) => s + e.price * e.quantity);
    return price + extrasTotal;
  }

  double get total => itemTotal ?? effectiveUnit * quantity;
}

class _Extra {
  final String name;
  final double price;
  final int quantity;
  const _Extra(
      {required this.name, required this.price, required this.quantity});
  factory _Extra.fromMap(Map<String, dynamic> m) => _Extra(
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
      );
}

class _OrderMeta {
  final int? estimatedPrepTime;
  final String? orderNotes;
  final String? restaurantPhone;
  final String? buyerPhone;
  final String? status;

  const _OrderMeta({
    this.estimatedPrepTime,
    this.orderNotes,
    this.restaurantPhone,
    this.buyerPhone,
    this.status,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class FoodReceiptDetailScreen extends StatefulWidget {
  final String receiptId;

  const FoodReceiptDetailScreen({Key? key, required this.receiptId})
      : super(key: key);

  @override
  State<FoodReceiptDetailScreen> createState() =>
      _FoodReceiptDetailScreenState();
}

class _FoodReceiptDetailScreenState extends State<FoodReceiptDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  _FoodReceiptDetail? _receipt;
  List<_FoodOrderItem> _items = [];
  _OrderMeta _meta = const _OrderMeta();
  bool _copySuccess = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'not_authenticated';
        _isLoading = false;
      });
      return;
    }
    try {
      // 1. Receipt from user sub-collection
      final receiptSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('foodReceipts')
          .doc(widget.receiptId)
          .get();

      if (!receiptSnap.exists) {
        setState(() {
          _error = 'not_found';
          _isLoading = false;
        });
        return;
      }

      final receipt = _FoodReceiptDetail.fromDoc(receiptSnap);

      // 2. Order doc for items + meta
      List<_FoodOrderItem> items = [];
      _OrderMeta meta = const _OrderMeta();
      if (receipt.orderId.isNotEmpty) {
        final orderSnap = await FirebaseFirestore.instance
            .collection('orders-food')
            .doc(receipt.orderId)
            .get();
        if (orderSnap.exists) {
          final od = orderSnap.data()!;
          final rawItems = od['items'];
          items = rawItems is List
              ? rawItems
                  .whereType<Map<String, dynamic>>()
                  .map(_FoodOrderItem.fromMap)
                  .toList()
              : [];
          meta = _OrderMeta(
            estimatedPrepTime: (od['estimatedPrepTime'] as num?)?.toInt(),
            orderNotes: od['orderNotes'] as String?,
            restaurantPhone: od['restaurantPhone'] as String?,
            buyerPhone: od['buyerPhone'] as String?,
            status: od['status'] as String?,
          );
        }
      }

      setState(() {
        _receipt = receipt;
        _items = items;
        _meta = meta;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _downloadPdf() async {
    String? url = _receipt?.downloadUrl;
    if (url == null || url.isEmpty) {
      final path = _receipt?.filePath;
      if (path != null && path.isNotEmpty) {
        try {
          url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        } catch (_) {}
      }
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
    if (_receipt == null) return;
    Clipboard.setData(ClipboardData(text: _receipt!.orderId));
    setState(() => _copySuccess = true);
    Future.delayed(const Duration(seconds: 2),
        () => mounted ? setState(() => _copySuccess = false) : null);
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String _formatDate(DateTime ts) => DateFormat('dd/MM/yyyy HH:mm').format(ts);

  String _localizePaymentMethod(String method, AppLocalizations l10n) {
    switch (method.toLowerCase()) {
      case 'pay_at_door':
        return l10n.payAtDoor;
      case 'card':
        return l10n.card;
      case 'cash':
        return l10n.cash;
      default:
        return method;
    }
  }

  String _localizeDeliveryType(String type, AppLocalizations l10n) =>
      type == 'pickup' ? l10n.pickup : l10n.delivery;

  String _localizeStatus(String? status, AppLocalizations l10n) {
    switch (status) {
      case 'pending':
        return l10n.foodStatusPending;
      case 'accepted':
      case 'confirmed':
        return l10n.foodStatusAccepted;
      case 'preparing':
        return l10n.foodStatusPreparing;
      case 'ready':
        return l10n.foodStatusReady;
      case 'delivered':
        return l10n.foodStatusDelivered;
      case 'completed':
        return l10n.foodStatusCompleted;
      case 'cancelled':
        return l10n.foodStatusCancelled;
      default:
        return status ?? '';
    }
  }

  // ── Shared card decoration ────────────────────────────────────────────────

  BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.grey.withOpacity(0.08),
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
      );

  Color _innerBg(bool isDark) =>
      isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC);

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(l10n, isDark),
            _isLoading
                ? SliverFillRemaining(child: _buildLoadingState(isDark))
                : _error != null
                    ? SliverFillRemaining(child: _buildErrorState(l10n, isDark))
                    : _receipt == null
                        ? const SliverFillRemaining(child: SizedBox.shrink())
                        : SliverList(
                            delegate: SliverChildListDelegate([
                              FadeTransition(
                                opacity: _fadeAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 32),
                                    child: Column(
                                      children: [
                                        _buildHeaderCard(l10n, isDark),
                                        const SizedBox(height: 12),
                                        _buildOrderInfoCard(l10n, isDark),
                                        if (!_receipt!.isPickup &&
                                            _receipt!.deliveryAddress !=
                                                null) ...[
                                          const SizedBox(height: 12),
                                          _buildDeliveryAddressCard(
                                              l10n, isDark),
                                        ],
                                        if (_items.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          _buildItemsCard(l10n, isDark),
                                        ],
                                        const SizedBox(height: 12),
                                        _buildPriceSummaryCard(l10n, isDark),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),
          ],
        ),
      ),
    );
  }

  // ── Sliver App Bar ────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(AppLocalizations l10n, bool isDark) {
    final hasPdf = (_receipt?.downloadUrl?.isNotEmpty == true) ||
        (_receipt?.filePath?.isNotEmpty == true);
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      snap: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white),
        ),
      ),
      actions: [
        if (hasPdf)
          Container(
            margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: IconButton(
              onPressed: _downloadPdf,
              icon: const Icon(FeatherIcons.download,
                  size: 16, color: Colors.white),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF97316), Color(0xFFEF4444)],
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
                          l10n.receiptDetails,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (_receipt != null)
                          Text(
                            _receipt!.restaurantName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(FeatherIcons.fileText,
                        size: 24, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildShimmerCard(bool isDark, {required double height}) =>
      Shimmer.fromColors(
        baseColor:
            isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[300]!,
        highlightColor:
            isDark ? const Color.fromARGB(255, 52, 48, 75) : Colors.grey[100]!,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

  Widget _buildLoadingState(bool isDark) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildShimmerCard(isDark, height: 120),
            const SizedBox(height: 12),
            _buildShimmerCard(isDark, height: 180),
            const SizedBox(height: 12),
            _buildShimmerCard(isDark, height: 200),
            const SizedBox(height: 12),
            _buildShimmerCard(isDark, height: 120),
          ],
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildErrorState(AppLocalizations l10n, bool isDark) {
    final isNotFound = _error == 'not_found';
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isNotFound ? FeatherIcons.fileText : Icons.error_outline_rounded,
              size: 40,
              color: const Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isNotFound ? l10n.receiptNotFound : l10n.failedToLoadOrder,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (!isNotFound) ...[
            Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(FeatherIcons.refreshCw, size: 16),
              label: Text(l10n.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.goBack,
                  style: const TextStyle(color: Color(0xFFF97316))),
            ),
          ],
        ],
      ),
    );
  }

  // ── Header card ───────────────────────────────────────────────────────────

  Widget _buildHeaderCard(AppLocalizations l10n, bool isDark) {
    final r = _receipt!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF97316).withOpacity(isDark ? 0.15 : 0.08),
            const Color(0xFFEF4444).withOpacity(isDark ? 0.15 : 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF97316).withOpacity(isDark ? 0.2 : 0.15),
        ),
      ),
      child: Column(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.restaurant_menu_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          // Restaurant name
          Text(
            r.restaurantName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Date
          Text(
            _formatDate(r.timestamp),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 12),
          // Payment status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: r.isPaid
                  ? Colors.green.withOpacity(isDark ? 0.15 : 0.1)
                  : Colors.amber.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: r.isPaid
                    ? Colors.green.withOpacity(0.3)
                    : Colors.amber.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  r.isPaid
                      ? Icons.check_circle_outline
                      : Icons.payments_outlined,
                  size: 14,
                  color: r.isPaid ? Colors.green : Colors.amber[700],
                ),
                const SizedBox(width: 6),
                Text(
                  r.isPaid ? l10n.paidOnline : l10n.payAtDoor,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: r.isPaid ? Colors.green : Colors.amber[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card wrapper ──────────────────────────────────────────────────

  Widget _buildSection({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: _cardDecoration(isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ── Info row ──────────────────────────────────────────────────────────────

  Widget _buildInfoRow({
    required bool isDark,
    required String label,
    required Widget value,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ),
              value,
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: isDark ? Colors.white10 : Colors.grey.shade100,
          ),
      ],
    );
  }

  Widget _infoText(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
        ),
      );

  // ── Order info card ───────────────────────────────────────────────────────

  Widget _buildOrderInfoCard(AppLocalizations l10n, bool isDark) {
    final r = _receipt!;
    return _buildSection(
      isDark: isDark,
      icon: FeatherIcons.info,
      iconColor: const Color(0xFFF97316),
      title: l10n.orderInformation,
      child: Column(
        children: [
          // Order ID + copy
          _buildInfoRow(
            isDark: isDark,
            label: l10n.orderNumber,
            value: Row(
              children: [
                Text(
                  '#${r.orderId.substring(0, r.orderId.length.clamp(0, 8)).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _copyOrderId,
                  child: Icon(
                    _copySuccess
                        ? Icons.check_circle_outline
                        : FeatherIcons.copy,
                    size: 14,
                    color: _copySuccess
                        ? Colors.green
                        : (isDark ? Colors.grey[400] : Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
          // Payment method
          _buildInfoRow(
            isDark: isDark,
            label: l10n.paymentMethod,
            value: Row(
              children: [
                Icon(
                  r.paymentMethod == 'card'
                      ? FeatherIcons.creditCard
                      : FeatherIcons.dollarSign,
                  size: 13,
                  color: r.paymentMethod == 'card'
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 5),
                _infoText(
                    _localizePaymentMethod(r.paymentMethod, l10n), isDark),
              ],
            ),
          ),
          // Delivery type
          _buildInfoRow(
            isDark: isDark,
            label: l10n.deliveryType,
            value: Text(
              _localizeDeliveryType(r.deliveryType, l10n),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: r.isPickup ? Colors.blue : Colors.green,
              ),
            ),
          ),
          // Status
          if (_meta.status != null && _meta.status!.isNotEmpty)
            _buildInfoRow(
              isDark: isDark,
              label: l10n.orderStatus,
              value: _infoText(_localizeStatus(_meta.status, l10n), isDark),
            ),
          // Prep time
          if (_meta.estimatedPrepTime != null && _meta.estimatedPrepTime! > 0)
            _buildInfoRow(
              isDark: isDark,
              label: l10n.prepTime,
              value: Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 13, color: Color(0xFFF97316)),
                  const SizedBox(width: 5),
                  _infoText(
                      '${_meta.estimatedPrepTime} ${l10n.minutes}', isDark),
                ],
              ),
            ),
          // Restaurant phone
          if (_meta.restaurantPhone != null &&
              _meta.restaurantPhone!.isNotEmpty)
            _buildInfoRow(
              isDark: isDark,
              label: l10n.restaurantPhone,
              value: Row(
                children: [
                  const Icon(Icons.phone, size: 13, color: Color(0xFF10B981)),
                  const SizedBox(width: 5),
                  _infoText(_meta.restaurantPhone!, isDark),
                ],
              ),
              isLast: true,
            ),
        ],
      ),
    );
  }

  // ── Delivery address card ─────────────────────────────────────────────────

  Widget _buildDeliveryAddressCard(AppLocalizations l10n, bool isDark) {
    final addr = _receipt!.deliveryAddress!;
    return _buildSection(
      isDark: isDark,
      icon: FeatherIcons.mapPin,
      iconColor: const Color(0xFF10B981),
      title: l10n.deliveryAddress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _innerBg(isDark),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [addr.addressLine1, addr.addressLine2]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(', '),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              addr.city,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
            if (addr.phoneNumber != null && addr.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.phone,
                        size: 12, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    addr.phoneNumber!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Items card ────────────────────────────────────────────────────────────

  Widget _buildItemsCard(AppLocalizations l10n, bool isDark) {
    return _buildSection(
      isDark: isDark,
      icon: FeatherIcons.shoppingBag,
      iconColor: const Color(0xFFF97316),
      title: l10n.orderedItems,
      child: Column(
        children: [
          // Item rows
          ..._items.asMap().entries.map((e) {
            final item = e.value;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: e.key == _items.length - 1 ? 0 : 10),
              child: _buildItemRow(item, isDark, l10n),
            );
          }),

          // Order notes
          if (_meta.orderNotes != null && _meta.orderNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _innerBg(isDark),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey.shade100,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderNotes,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.grey[500] : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _meta.orderNotes!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(
      _FoodOrderItem item, bool isDark, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _innerBg(isDark),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Qty badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.quantity}×',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF97316),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Text(
                '${item.total.toStringAsFixed(0)} ${_receipt!.currency}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF97316),
                ),
              ),
            ],
          ),
          if (item.quantity > 1) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Text(
                '${item.effectiveUnit.toStringAsFixed(0)} ${_receipt!.currency} ${l10n.each}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
              ),
            ),
          ],
          // Extras
          if (item.extras.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.extras.map((ext) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    [
                      localizeExtra(ext.name, l10n),
                      if (ext.quantity > 1) '×${ext.quantity}',
                      if (ext.price > 0) '+${ext.price.toStringAsFixed(0)}',
                    ].join(' '),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          // Special notes
          if (item.specialNotes != null && item.specialNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 12,
                    color: isDark ? Colors.grey[400] : const Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.specialNotes!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Price summary card ────────────────────────────────────────────────────

  Widget _buildPriceSummaryCard(AppLocalizations l10n, bool isDark) {
    final r = _receipt!;
    return _buildSection(
      isDark: isDark,
      icon: FeatherIcons.dollarSign,
      iconColor: const Color(0xFFF97316),
      title: l10n.priceSummary,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _innerBg(isDark),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  isDark: isDark,
                  label: l10n.subtotal,
                  value: _infoText(
                      '${r.subtotal.toStringAsFixed(0)} ${r.currency}', isDark),
                ),
                if (!r.isPickup)
                  _buildInfoRow(
                    isDark: isDark,
                    label: l10n.deliveryFee,
                    value: Text(
                      r.deliveryFee == 0
                          ? l10n.free
                          : '${r.deliveryFee.toStringAsFixed(0)} ${r.currency}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: r.deliveryFee == 0
                            ? Colors.green
                            : (isDark ? Colors.white : const Color(0xFF1A1A1A)),
                      ),
                    ),
                    isLast: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Grand total
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF97316).withOpacity(isDark ? 0.12 : 0.06),
                  const Color(0xFFEF4444).withOpacity(isDark ? 0.12 : 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF97316).withOpacity(isDark ? 0.2 : 0.15),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.total,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                Text(
                  '${r.totalPrice.toStringAsFixed(0)} ${r.currency}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF97316),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Payment note
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                r.isPaid ? Icons.check_circle_outline : Icons.payments_outlined,
                size: 13,
                color: r.isPaid ? Colors.green : Colors.amber[700],
              ),
              const SizedBox(width: 6),
              Text(
                r.isPaid ? l10n.paidOnlineNote : l10n.payAtDoorNote,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: r.isPaid ? Colors.green : Colors.amber[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
