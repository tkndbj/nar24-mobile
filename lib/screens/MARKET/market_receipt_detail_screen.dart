// lib/screens/receipts/market_receipt_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local models
// ─────────────────────────────────────────────────────────────────────────────

class _MarketReceiptDetail {
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
  final String buyerName;
  final _DeliveryAddress? deliveryAddress;
  final String? filePath;
  final String? downloadUrl;

  const _MarketReceiptDetail({
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
    required this.buyerName,
    this.deliveryAddress,
    this.filePath,
    this.downloadUrl,
  });

  factory _MarketReceiptDetail.fromDoc(DocumentSnapshot doc) {
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
    return _MarketReceiptDetail(
      id: doc.id,
      orderId: (d['orderId'] as String?) ?? '',
      receiptId: (d['receiptId'] as String?) ?? '',
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      subtotal: (d['subtotal'] as num?)?.toDouble() ??
          (d['totalPrice'] as num?)?.toDouble() ??
          0,
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] as String?) ?? 'TL',
      timestamp: t,
      paymentMethod: (d['paymentMethod'] as String?) ?? '',
      isPaid: (d['isPaid'] as bool?) ?? false,
      deliveryType: (d['deliveryType'] as String?) ?? 'delivery',
      buyerName: (d['buyerName'] as String?) ?? '',
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
        addressLine1: (m['addressLine1'] as String?) ?? '',
        addressLine2: m['addressLine2'] as String?,
        city: (m['city'] as String?) ?? '',
        phoneNumber: m['phoneNumber'] as String?,
      );
}

class _MarketOrderItem {
  final String itemId;
  final String name;
  final String brand;
  final String type;
  final String category;
  final double price;
  final int quantity;
  final double? itemTotal;

  const _MarketOrderItem({
    required this.itemId,
    required this.name,
    required this.brand,
    required this.type,
    required this.category,
    required this.price,
    required this.quantity,
    this.itemTotal,
  });

  double get total => itemTotal ?? (price * quantity);

  factory _MarketOrderItem.fromMap(Map<String, dynamic> m) => _MarketOrderItem(
        itemId: (m['itemId'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        brand: (m['brand'] as String?) ?? '',
        type: (m['type'] as String?) ?? '',
        category: (m['category'] as String?) ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        itemTotal: (m['itemTotal'] as num?)?.toDouble(),
      );
}

class _OrderMeta {
  final String? orderNotes;
  final String? buyerPhone;
  final String? status;

  const _OrderMeta({this.orderNotes, this.buyerPhone, this.status});
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MarketReceiptDetailScreen extends StatefulWidget {
  final String receiptId;

  const MarketReceiptDetailScreen({super.key, required this.receiptId});

  @override
  State<MarketReceiptDetailScreen> createState() =>
      _MarketReceiptDetailScreenState();
}

class _MarketReceiptDetailScreenState extends State<MarketReceiptDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  _MarketReceiptDetail? _receipt;
  List<_MarketOrderItem> _items = [];
  _OrderMeta _meta = const _OrderMeta();
  bool _copySuccess = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
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
      final receiptSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('marketReceipts')
          .doc(widget.receiptId)
          .get();

      if (!receiptSnap.exists) {
        setState(() {
          _error = 'not_found';
          _isLoading = false;
        });
        return;
      }

      final receipt = _MarketReceiptDetail.fromDoc(receiptSnap);

      List<_MarketOrderItem> items = [];
      _OrderMeta meta = const _OrderMeta();
      if (receipt.orderId.isNotEmpty) {
        final orderSnap = await FirebaseFirestore.instance
            .collection('orders-market')
            .doc(receipt.orderId)
            .get();
        if (orderSnap.exists) {
          final od = orderSnap.data()!;
          final rawItems = od['items'];
          items = rawItems is List
              ? rawItems
                  .whereType<Map<String, dynamic>>()
                  .map(_MarketOrderItem.fromMap)
                  .toList()
              : [];
          meta = _OrderMeta(
            orderNotes: od['orderNotes'] as String?,
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
      _animCtrl.forward();
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
        } catch (_) {
          // PDF not available
        }
      }
    }
    if (url != null && url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.marketReceiptPdfNotReady)),
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

  String _fmtDate(DateTime ts) => DateFormat('dd/MM/yyyy HH:mm').format(ts);

  String _localizeStatus(String? status, AppLocalizations l10n) {
    switch (status) {
      case 'pending':
        return l10n.marketOrderStatusPending;
      case 'confirmed':
        return l10n.marketOrderStatusConfirmed;
      case 'preparing':
        return l10n.marketOrderStatusPreparing;
      case 'out_for_delivery':
        return l10n.marketOrderStatusOutForDelivery;
      case 'delivered':
        return l10n.marketOrderStatusDelivered;
      case 'completed':
        return l10n.marketOrderStatusCompleted;
      case 'rejected':
        return l10n.marketOrderStatusRejected;
      case 'cancelled':
        return l10n.marketOrderStatusCancelled;
      default:
        return status ?? '';
    }
  }

  // ── Shared decoration ─────────────────────────────────────────────────────

  BoxDecoration _cardDecor(bool isDark) => BoxDecoration(
        color: isDark ? const Color(0xFF211F31) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.grey.withOpacity(0.08)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
        body: CustomScrollView(
          slivers: [
            _buildAppBar(isDark),
            _isLoading
                ? SliverFillRemaining(child: _buildLoading(isDark))
                : _error != null
                    ? SliverFillRemaining(child: _buildError(isDark))
                    : _receipt == null
                        ? const SliverFillRemaining(child: SizedBox.shrink())
                        : SliverList(
                            delegate: SliverChildListDelegate([
                              FadeTransition(
                                opacity: _fadeAnim,
                                child: SlideTransition(
                                  position: _slideAnim,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 32),
                                    child: Column(children: [
                                      _buildHeaderCard(isDark),
                                      const SizedBox(height: 12),
                                      _buildOrderInfoCard(isDark),
                                      if (_receipt!.deliveryAddress !=
                                          null) ...[
                                        const SizedBox(height: 12),
                                        _buildAddressCard(isDark),
                                      ],
                                      if (_items.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        _buildItemsCard(isDark),
                                      ],
                                      const SizedBox(height: 12),
                                      _buildSummaryCard(isDark),
                                    ]),
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

  // ── App bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar(bool isDark) {
    final hasPdf = (_receipt?.downloadUrl?.isNotEmpty == true) ||
        (_receipt?.filePath?.isNotEmpty == true);
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
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
              colors: [Color(0xFF10B981), Color(0xFF059669)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(AppLocalizations.of(context)!.marketReceiptTitle,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text(AppLocalizations.of(context)!.marketBrandName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70)),
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
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading(bool isDark) {
    final base = isDark ? const Color(0xFF211F31) : Colors.grey[300]!;
    final highlight = isDark ? const Color(0xFF3A3850) : Colors.grey[100]!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          children: List.generate(
              4,
              (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Shimmer.fromColors(
                      baseColor: base,
                      highlightColor: highlight,
                      child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                              color: base,
                              borderRadius: BorderRadius.circular(16))),
                    ),
                  ))),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final isNotFound = _error == 'not_found';
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(
              isNotFound ? FeatherIcons.fileText : Icons.error_outline_rounded,
              size: 40,
              color: Colors.red),
        ),
        const SizedBox(height: 20),
        Text(
            isNotFound
                ? l10n.marketReceiptNotFound
                : l10n.marketReceiptLoadError,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
            textAlign: TextAlign.center),
        if (!isNotFound) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[400] : Colors.grey[600]),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(FeatherIcons.refreshCw, size: 16),
            label: Text(l10n.marketOrdersTryAgain),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
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
            child: Text(l10n.marketReceiptGoBack,
                style: const TextStyle(color: Colors.green)),
          ),
        ],
      ]),
    );
  }

  // ── Header card ───────────────────────────────────────────────────────────

  Widget _buildHeaderCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final r = _receipt!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.withOpacity(isDark ? 0.15 : 0.08),
            const Color(0xFF059669).withOpacity(isDark ? 0.15 : 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.green.withOpacity(isDark ? 0.2 : 0.15)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.shopping_bag_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(height: 14),
        Text(l10n.marketBrandName,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(_fmtDate(r.timestamp),
            style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[500])),
        const SizedBox(height: 12),
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
                    : Colors.amber.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                r.isPaid ? Icons.check_circle_outline : Icons.payments_outlined,
                size: 14,
                color: r.isPaid ? Colors.green : Colors.amber[700]),
            const SizedBox(width: 6),
            Text(
                r.isPaid
                    ? l10n.marketOrderPaidOnline
                    : l10n.marketOrderPaymentAtDoor,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: r.isPaid ? Colors.green : Colors.amber[700])),
          ]),
        ),
      ]),
    );
  }

  // ── Section wrapper ───────────────────────────────────────────────────────

  Widget _section({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: _cardDecor(isDark),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  // ── Info row ──────────────────────────────────────────────────────────────

  Widget _infoRow(bool isDark, String label, Widget value,
      {bool isLast = false}) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[500])),
          value,
        ]),
      ),
      if (!isLast)
        Divider(
            height: 1, color: isDark ? Colors.white10 : Colors.grey.shade100),
    ]);
  }

  Widget _infoText(String text, bool isDark) => Text(text,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A1A1A)));

  // ── Order info card ───────────────────────────────────────────────────────

  Widget _buildOrderInfoCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final r = _receipt!;
    return _section(
      isDark: isDark,
      icon: FeatherIcons.info,
      iconColor: Colors.green,
      title: l10n.marketReceiptOrderInfo,
      child: Column(children: [
        _infoRow(
            isDark,
            l10n.marketReceiptOrderNumber,
            Row(children: [
              Text(
                  '#${r.orderId.substring(0, r.orderId.length.clamp(0, 8)).toUpperCase()}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _copyOrderId,
                child: Icon(
                    _copySuccess
                        ? Icons.check_circle_outline
                        : FeatherIcons.copy,
                    size: 14,
                    color: _copySuccess ? Colors.green : Colors.grey[400]),
              ),
            ])),
        _infoRow(
            isDark,
            l10n.marketReceiptPaymentMethod,
            Row(children: [
              Icon(
                  r.paymentMethod == 'card'
                      ? FeatherIcons.creditCard
                      : FeatherIcons.dollarSign,
                  size: 13,
                  color: r.paymentMethod == 'card'
                      ? const Color(0xFF6366F1)
                      : const Color(0xFFF59E0B)),
              const SizedBox(width: 5),
              _infoText(
                  r.paymentMethod == 'card'
                      ? l10n.marketOrderPaymentCard
                      : l10n.marketOrderPaymentAtDoor,
                  isDark),
            ])),
        _infoRow(
            isDark,
            l10n.marketReceiptDelivery,
            Text(l10n.marketReceiptDelivery,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green))),
        if (_meta.status != null && _meta.status!.isNotEmpty)
          _infoRow(
              isDark,
              l10n.marketReceiptStatus,
              _infoText(_localizeStatus(_meta.status, l10n), isDark),
              isLast: true),
      ]),
    );
  }

  // ── Address card ──────────────────────────────────────────────────────────

  Widget _buildAddressCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final addr = _receipt!.deliveryAddress!;
    return _section(
      isDark: isDark,
      icon: FeatherIcons.mapPin,
      iconColor: const Color(0xFF10B981),
      title: l10n.marketReceiptDeliveryAddress,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _innerBg(isDark), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              [addr.addressLine1, addr.addressLine2]
                  .where((s) => s != null && s.isNotEmpty)
                  .join(', '),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
          const SizedBox(height: 3),
          Text(addr.city,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
          if (addr.phoneNumber != null && addr.phoneNumber!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6)),
                child:
                    const Icon(Icons.phone, size: 12, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 8),
              Text(addr.phoneNumber!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
            ]),
          ],
        ]),
      ),
    );
  }

  // ── Items card ────────────────────────────────────────────────────────────

  Widget _buildItemsCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    return _section(
      isDark: isDark,
      icon: FeatherIcons.shoppingBag,
      iconColor: Colors.green,
      title: l10n.marketReceiptOrderedItems,
      child: Column(children: [
        ..._items.asMap().entries.map((e) {
          final item = e.value;
          return Padding(
            padding:
                EdgeInsets.only(bottom: e.key == _items.length - 1 ? 0 : 10),
            child: _buildItemRow(item, isDark),
          );
        }),
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
                      : Colors.grey.shade100),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.marketReceiptOrderNoteHeader,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color:
                                isDark ? Colors.grey[500] : Colors.grey[400])),
                    const SizedBox(height: 3),
                    Text(_meta.orderNotes!,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                isDark ? Colors.grey[300] : Colors.grey[700])),
                  ])),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildItemRow(_MarketOrderItem item, bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final cat = kMarketCategoryMap[item.category];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _innerBg(isDark), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Qty badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${item.quantity}×',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.green)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (item.brand.isNotEmpty)
                  Text(item.brand,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700])),
                Text(item.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : const Color(0xFF1A1A1A))),
                if (item.type.isNotEmpty)
                  Text(item.type,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[600])),
              ])),
          Text('${item.total.toStringAsFixed(0)} ${_receipt!.currency}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.green)),
        ]),
        if (item.quantity > 1) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
                l10n.marketReceiptPerUnit(
                    '${item.price.toStringAsFixed(0)} ${_receipt!.currency}'),
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[400])),
          ),
        ],
      ]),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────────

  Widget _buildSummaryCard(bool isDark) {
    final l10n = AppLocalizations.of(context)!;
    final r = _receipt!;
    return _section(
      isDark: isDark,
      icon: FeatherIcons.dollarSign,
      iconColor: Colors.green,
      title: l10n.marketReceiptPriceSummary,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _innerBg(isDark), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            _infoRow(
                isDark,
                l10n.marketOrderSubtotalLabel,
                _infoText(
                    '${r.subtotal.toStringAsFixed(0)} ${r.currency}', isDark)),
            _infoRow(
                isDark,
                l10n.marketOrderDeliveryLabel,
                Text(
                    r.deliveryFee == 0
                        ? l10n.marketOrderDeliveryFree
                        : '${r.deliveryFee.toStringAsFixed(0)} ${r.currency}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: r.deliveryFee == 0
                            ? Colors.green
                            : (isDark
                                ? Colors.white
                                : const Color(0xFF1A1A1A)))),
                isLast: true),
          ]),
        ),
        const SizedBox(height: 10),
        // Grand total
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.green.withOpacity(isDark ? 0.12 : 0.06),
              const Color(0xFF059669).withOpacity(isDark ? 0.12 : 0.06),
            ]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.green.withOpacity(isDark ? 0.2 : 0.15)),
          ),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l10n.marketOrderTotalLabel,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
            Text('${r.totalPrice.toStringAsFixed(0)} ${r.currency}',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.green)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(r.isPaid ? Icons.check_circle_outline : Icons.payments_outlined,
              size: 13, color: r.isPaid ? Colors.green : Colors.amber[700]),
          const SizedBox(width: 6),
          Text(
              r.isPaid
                  ? l10n.marketReceiptOnlinePaymentReceived
                  : l10n.marketReceiptPayDuringDelivery,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: r.isPaid ? Colors.green : Colors.amber[700])),
        ]),
      ]),
    );
  }
}
