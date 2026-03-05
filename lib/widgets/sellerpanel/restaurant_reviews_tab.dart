import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

class _ReviewData {
  final String id;
  final double rating;
  final String comment;
  final String buyerName;
  final Timestamp? timestamp;

  const _ReviewData({
    required this.id,
    required this.rating,
    required this.comment,
    required this.buyerName,
    this.timestamp,
  });

  factory _ReviewData.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _ReviewData(
      id: doc.id,
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      comment: d['comment'] as String? ?? '',
      buyerName: d['buyerName'] as String? ?? '',
      timestamp: d['timestamp'] as Timestamp?,
    );
  }
}

// ─── Constants ───────────────────────────────────────────────────────────────

const int _pageSize = 15;

// ─── Main Widget ─────────────────────────────────────────────────────────────

class RestaurantReviewsTab extends StatefulWidget {
  final String restaurantId;

  /// Optional pre-loaded averageRating / reviewCount from the shop document,
  /// matching the web's `selectedShop.averageRating` / `selectedShop.reviewCount`.
  final double averageRating;
  final int totalReviewCount;

  const RestaurantReviewsTab({
    Key? key,
    required this.restaurantId,
    this.averageRating = 0,
    this.totalReviewCount = 0,
  }) : super(key: key);

  @override
  State<RestaurantReviewsTab> createState() => _RestaurantReviewsTabState();
}

class _RestaurantReviewsTabState extends State<RestaurantReviewsTab> {
  static const _collection = 'restaurants';
  static const _subCollection = 'food-reviews';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<_ReviewData> _reviews = [];
  DocumentSnapshot? _lastDocument;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReviews(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll-triggered pagination (mirrors infinite scroll on web) ──────────

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _fetchReviews(reset: false);
    }
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetchReviews({required bool reset}) async {
    if (!mounted) return;
    if (!reset && (_loadingMore || !_hasMore)) return;

    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });

    try {
      Query q = _firestore
          .collection(_collection)
          .doc(widget.restaurantId)
          .collection(_subCollection)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (!reset && _lastDocument != null) {
        q = q.startAfterDocument(_lastDocument!);
      }

      final snapshot = await q.get();
      if (!mounted) return;

      final newReviews = snapshot.docs.map(_ReviewData.fromDoc).toList();

      setState(() {
        if (reset) {
          _reviews = newReviews;
        } else {
          final existingIds = _reviews.map((r) => r.id).toSet();
          _reviews.addAll(newReviews.where((r) => !existingIds.contains(r.id)));
        }
        _lastDocument =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDocument;
        _hasMore = snapshot.docs.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMd(locale == 'tr' ? 'tr_TR' : 'en_US')
        .format(ts.toDate());
  }

  double get _computedAverage {
    if (widget.averageRating > 0) return widget.averageRating;
    if (_reviews.isEmpty) return 0;
    return _reviews.map((r) => r.rating).reduce((a, b) => a + b) /
        _reviews.length;
  }

  int get _computedTotal =>
      widget.totalReviewCount > 0 ? widget.totalReviewCount : _reviews.length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _reviews.isEmpty) return _buildLoadingState();
    if (_error != null) return _buildErrorState();

    return RefreshIndicator(
      color: const Color(0xFFFF6200),
      onRefresh: () => _fetchReviews(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Summary card — mirrors web's amber summary block
                if (_reviews.isNotEmpty) ...[
                  _SummaryCard(
                    average: _computedAverage,
                    totalCount: _computedTotal,
                  ),
                  const SizedBox(height: 12),
                ],

                // Empty state
                if (_reviews.isEmpty)
                  _buildEmptyState()
                else
                  ..._reviews.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReviewCard(
                          review: r,
                          formattedDate: _formatDate(r.timestamp),
                        ),
                      )),

                // Load-more indicator
                if (_loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF6200),
                        ),
                      ),
                    ),
                  ),

                // End-of-list caption
                if (!_hasMore && _reviews.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        AppLocalizations.of(context).endOfReviews,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── States ────────────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).errorLoadingReviews,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _fetchReviews(reset: true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).retry),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6200)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.withOpacity(0.1)
                    : const Color(0xFFFFFBEB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_outline_rounded,
                  size: 40, color: Color(0xFFFBBF24)),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noReviews,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).noReviewsDescription,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Summary Card ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double average;
  final int totalCount;

  const _SummaryCard({required this.average, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.withOpacity(0.15)
                  : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.star_rounded,
                color: Color(0xFFFBBF24), size: 28),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StarRow(rating: average.round()),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).basedOn(totalCount),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Review Card ──────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final _ReviewData review;
  final String formattedDate;

  const _ReviewCard({required this.review, required this.formattedDate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name/stars + date
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withOpacity(0.15)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant_rounded,
                    size: 18, color: Color(0xFFFF6200)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.buyerName.isNotEmpty
                          ? review.buyerName
                          : l10n.anonymous,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _StarRow(rating: review.rating.round()),
                  ],
                ),
              ),
              Text(
                formattedDate,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ),
            ],
          ),

          // Comment
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Star Row ────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final int rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 13,
          color: i < rating ? const Color(0xFFFBBF24) : Colors.grey[300],
        );
      }),
    );
  }
}
