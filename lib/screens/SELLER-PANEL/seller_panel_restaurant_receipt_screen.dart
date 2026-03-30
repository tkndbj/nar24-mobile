import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';

import '../../../generated/l10n/app_localizations.dart';

// ── Model ──────────────────────────────────────────────────────────────────────

class _RestaurantReceipt {
  final String id;
  final String orderId;
  final String buyerName;
  final double totalPrice;
  final String currency;
  final String paymentMethod;
  final bool isPaid;
  final String deliveryType;
  final String downloadUrl;
  final Timestamp? orderDate;
  final Timestamp? timestamp;

  const _RestaurantReceipt({
    required this.id,
    required this.orderId,
    required this.buyerName,
    required this.totalPrice,
    required this.currency,
    required this.paymentMethod,
    required this.isPaid,
    required this.deliveryType,
    required this.downloadUrl,
    this.orderDate,
    this.timestamp,
  });

  factory _RestaurantReceipt.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _RestaurantReceipt(
      id: doc.id,
      orderId: (d['orderId'] as String?) ?? doc.id,
      buyerName: (d['buyerName'] as String?) ?? '—',
      totalPrice: ((d['totalPrice'] as num?) ?? 0).toDouble(),
      currency: (d['currency'] as String?) ?? 'TL',
      paymentMethod: (d['paymentMethod'] as String?) ?? '',
      isPaid: (d['isPaid'] as bool?) ?? false,
      deliveryType: (d['deliveryType'] as String?) ?? 'delivery',
      downloadUrl: (d['downloadUrl'] as String?) ?? '',
      orderDate: d['orderDate'] as Timestamp?,
      timestamp: d['timestamp'] as Timestamp?,
    );
  }

  Timestamp? get effectiveDate => orderDate ?? timestamp;

  String get shortId => id.substring(0, id.length.clamp(0, 8)).toUpperCase();
}

// ── Constants ──────────────────────────────────────────────────────────────────

const _kOrange = Color(0xFFFF6200);
const _kPageSize = 20;

// ── Screen ─────────────────────────────────────────────────────────────────────

class SellerPanelRestaurantReceiptScreen extends StatefulWidget {
  final String restaurantId;

  const SellerPanelRestaurantReceiptScreen({
    Key? key,
    required this.restaurantId,
  }) : super(key: key);

  @override
  State<SellerPanelRestaurantReceiptScreen> createState() =>
      _SellerPanelRestaurantReceiptScreenState();
}

class _SellerPanelRestaurantReceiptScreenState
    extends State<SellerPanelRestaurantReceiptScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _scrollController = ScrollController();

  List<_RestaurantReceipt> _receipts = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchReceipts();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_loadingMore &&
        _hasMore) {
      _fetchMore();
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────────

  Future<void> _fetchReceipts() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final snap = await _firestore
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orderReceipts')
          .orderBy('timestamp', descending: true)
          .limit(_kPageSize)
          .get();

      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      setState(() {
        _receipts = snap.docs.map(_RestaurantReceipt.fromDoc).toList();
        _hasMore = snap.docs.length == _kPageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching receipts: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMore() async {
    if (!mounted || _loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await _firestore
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('orderReceipts')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_kPageSize)
          .get();

      if (!mounted) return;
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      setState(() {
        _receipts.addAll(snap.docs.map(_RestaurantReceipt.fromDoc));
        _hasMore = snap.docs.length == _kPageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('Error fetching more receipts: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Download ──────────────────────────────────────────────────────────────────

 Future<void> _handleDownload(_RestaurantReceipt receipt) async {
  final l10n = AppLocalizations.of(context);

  if (receipt.downloadUrl.isEmpty) {
    _showSnackbar(l10n.restaurantReceiptsDownloadUrlNotFound, isError: true);
    return;
  }

  setState(() => _downloadingId = receipt.id);

  try {
    final uri = Uri.parse(receipt.downloadUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch URL');
    }
  } catch (e) {
    debugPrint('Download error: $e');
    _showSnackbar(l10n.restaurantReceiptsDownloadFailed, isError: true);
  } finally {
    if (mounted) setState(() => _downloadingId = null);
  }
}

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '—';
    final locale = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat(
      'd MMM y, HH:mm',
      locale == 'tr' ? 'tr_TR' : (locale == 'ru' ? 'ru_RU' : 'en_US'),
    );
    return fmt.format(ts.toDate().toLocal());
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : const Color(0xFFF9FAFB),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: _loading ? _buildSkeleton(isDark) : _buildBody(l10n, isDark),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.grey[900],
      title: Row(
        children: [
          Text(
            l10n.restaurantReceiptsTitle,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
          if (_receipts.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_receipts.length}${_hasMore ? '+' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey[500],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────────

  Widget _buildSkeleton(bool isDark) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade200;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: 10,
        separatorBuilder: (_, __) => const SizedBox(height: 1),
        itemBuilder: (_, i) => _SkeletonRow(isDark: isDark, base: base),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────────

  Widget _buildBody(AppLocalizations l10n, bool isDark) {
    if (_receipts.isEmpty) return _buildEmpty(l10n, isDark);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _receipts.length + (_hasMore || _loadingMore ? 1 : 0) + 1,
      itemBuilder: (context, index) {
        // List container header slot
        if (index == 0) {
          return _buildListCard(l10n, isDark);
        }
        // "Load more" / spinner slot
        if (index == _receipts.length + 1) {
          return _buildLoadMore(l10n, isDark);
        }
        // Never reached (list is inside _buildListCard)
        return const SizedBox.shrink();
      },
    );
  }

  // The whole receipt list lives in a single white card
  Widget _buildListCard(AppLocalizations l10n, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF28253A) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
            ),
          ),
          child: Column(
            children: List.generate(_receipts.length, (i) {
              final receipt = _receipts[i];
              final isLast = i == _receipts.length - 1;
              return Column(
                children: [
                  _buildReceiptRow(receipt, l10n, isDark),
                  if (!isLast)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    ),
                ],
              );
            }),
          ),
        ),
        if (!_hasMore && _receipts.length > _kPageSize)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: Text(
                l10n.restaurantReceiptsShowingAll(_receipts.length),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.white24 : Colors.grey[400],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Receipt row ───────────────────────────────────────────────────────────────

  Widget _buildReceiptRow(
    _RestaurantReceipt receipt,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final isDownloading = _downloadingId == receipt.id;
    final dateLabel = _formatDate(receipt.effectiveDate);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: receipt.downloadUrl.isNotEmpty
            ? () => _handleDownload(receipt)
            : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 18,
                  color: _kOrange,
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            receipt.buyerName,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.grey[900],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '#${receipt.shortId}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white38 : Colors.grey[400],
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Right side
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Price
                  Text(
                    '${receipt.totalPrice.toStringAsFixed(0)} ${receipt.currency}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _PaymentBadge(receipt: receipt, l10n: l10n),
                      const SizedBox(width: 4),
                      _DeliveryBadge(receipt: receipt, l10n: l10n),
                      if (receipt.isPaid) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: Color(0xFF10B981),
                        ),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(width: 8),

              // Download button
              _DownloadButton(
                isDownloading: isDownloading,
                hasUrl: receipt.downloadUrl.isNotEmpty,
                isDark: isDark,
                onTap: () => _handleDownload(receipt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Load more ─────────────────────────────────────────────────────────────────

  Widget _buildLoadMore(AppLocalizations l10n, bool isDark) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(_kOrange),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: OutlinedButton(
          onPressed: _fetchMore,
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(
            l10n.restaurantReceiptsLoadMore,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────────

  Widget _buildEmpty(AppLocalizations l10n, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 32,
                color: Color(0xFFFB923C),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.restaurantReceiptsEmptyTitle,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.restaurantReceiptsEmptyDescription,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _PaymentBadge extends StatelessWidget {
  final _RestaurantReceipt receipt;
  final AppLocalizations l10n;

  const _PaymentBadge({required this.receipt, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isCard = receipt.paymentMethod == 'card';
    final bg = isCard ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB);
    final fg = isCard ? const Color(0xFF2563EB) : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCard ? Icons.credit_card_rounded : Icons.payments_rounded,
            size: 10,
            color: fg,
          ),
          const SizedBox(width: 2),
          Text(
            isCard
                ? l10n.restaurantReceiptsPaymentCard
                : l10n.restaurantReceiptsPaymentDoor,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryBadge extends StatelessWidget {
  final _RestaurantReceipt receipt;
  final AppLocalizations l10n;

  const _DeliveryBadge({required this.receipt, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isPickup = receipt.deliveryType == 'pickup';
    final bg = isPickup ? const Color(0xFFF5F3FF) : const Color(0xFFF0FDFA);
    final fg = isPickup ? const Color(0xFF7C3AED) : const Color(0xFF0D9488);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPickup
                ? Icons.shopping_bag_outlined
                : Icons.local_shipping_outlined,
            size: 10,
            color: fg,
          ),
          const SizedBox(width: 2),
          Text(
            isPickup
                ? l10n.restaurantReceiptsDeliveryPickup
                : l10n.restaurantReceiptsDeliveryDelivery,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final bool isDownloading;
  final bool hasUrl;
  final bool isDark;
  final VoidCallback onTap;

  const _DownloadButton({
    required this.isDownloading,
    required this.hasUrl,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: (hasUrl && !isDownloading) ? onTap : null,
          child: Center(
            child: isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_kOrange),
                    ),
                  )
                : Icon(
                    Icons.download_rounded,
                    size: 15,
                    color: hasUrl
                        ? (isDark ? Colors.white60 : Colors.grey[600])
                        : Colors.grey[300],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Skeleton row ──────────────────────────────────────────────────────────────

class _SkeletonRow extends StatelessWidget {
  final bool isDark;
  final Color base;

  const _SkeletonRow({required this.isDark, required this.base});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF28253A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 120,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                height: 12,
                width: 60,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    height: 16,
                    width: 36,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    height: 16,
                    width: 44,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }
}