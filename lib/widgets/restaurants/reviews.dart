// lib/widgets/restaurants/reviews.dart
//
// Mirrors: components/restaurants/RestaurantReviews.tsx

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../generated/l10n/app_localizations.dart';
import '../cloudinary_image.dart';

const _kPageSize = 20;

// =============================================================================
// MODEL  —  mirrors FoodReview interface
// =============================================================================

class FoodReview {
  final String id;
  final String orderId;
  final String buyerId;
  final String? buyerName;
  final String restaurantId;
  final String? restaurantName;
  final int rating;
  final String comment;
  final Timestamp? timestamp;
  final List<String> imageUrls;

  const FoodReview({
    required this.id,
    required this.orderId,
    required this.buyerId,
    required this.restaurantId,
    required this.rating,
    required this.comment,
    this.buyerName,
    this.restaurantName,
    this.timestamp,
    this.imageUrls = const [],
  });

  factory FoodReview.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return FoodReview(
      id: doc.id,
      orderId: (d['orderId'] as String?) ?? '',
      buyerId: (d['buyerId'] as String?) ?? '',
      buyerName: d['buyerName'] as String?,
      restaurantId: (d['restaurantId'] as String?) ?? '',
      restaurantName: d['restaurantName'] as String?,
      rating: (d['rating'] as num?)?.toInt() ?? 0,
      comment: (d['comment'] as String?) ?? '',
      timestamp: d['timestamp'] as Timestamp?,
      imageUrls: (d['imageUrls'] as List<dynamic>?) // ← ADD
              ?.whereType<String>()
              .toList() ??
          [],
    );
  }
}

// =============================================================================
// ENTRY WIDGET
// =============================================================================

class RestaurantReviews extends StatefulWidget {
  final String restaurantId;
  final bool isDark;

  const RestaurantReviews({
    required this.restaurantId,
    required this.isDark,
    super.key,
  });

  @override
  State<RestaurantReviews> createState() => _RestaurantReviewsState();
}

class _RestaurantReviewsState extends State<RestaurantReviews> {
  final List<FoodReview> _reviews = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;

  /// Mirrors lastDocRef — cursor for pagination
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    _fetchReviews(reset: true);
  }

  /// Mirrors fetchReviews(reset: boolean) — initial load + load-more
  Future<void> _fetchReviews({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _lastDoc = null;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final col = FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('food-reviews');

      Query<Map<String, dynamic>> q =
          col.orderBy('timestamp', descending: true).limit(_kPageSize);

      if (!reset && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snapshot = await q.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDoc = snapshot.docs.last;
      }

      final fetched = snapshot.docs
          .map((doc) =>
              FoodReview.fromDoc(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();

      if (mounted) {
        setState(() {
          _hasMore = snapshot.docs.length == _kPageSize;
          if (reset) {
            _reviews
              ..clear()
              ..addAll(fetched);
          } else {
            _reviews.addAll(fetched);
          }
        });
      }
    } catch (e) {
      debugPrint('[RestaurantReviews] Fetch error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initial loading — mirrors if (isLoading) return <ReviewsSkeleton>
    if (_isLoading) {
      return _ReviewsSkeleton(isDark: widget.isDark);
    }

    // Empty state
    if (_reviews.isEmpty) {
      return _EmptyReviews(isDark: widget.isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 80),
      // reviews + optional load-more button
      itemCount: _reviews.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < _reviews.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ReviewCard(review: _reviews[i], isDark: widget.isDark),
          );
        }

        // Load more button — mirrors the hasMore footer
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Center(
            child: _LoadMoreButton(
              isLoadingMore: _isLoadingMore,
              isDark: widget.isDark,
              onTap: () => _fetchReviews(reset: false),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// REVIEW CARD  —  mirrors ReviewCard component
// =============================================================================

class _ReviewCard extends StatelessWidget {
  final FoodReview review;
  final bool isDark;

  const _ReviewCard({required this.review, required this.isDark});

  /// Mirrors maskName — masks first/last name characters
  String _maskName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.asMap().entries.map((entry) {
      final i = entry.key;
      final part = entry.value;
      if (part.length <= 1) return part;
      if (i == 0) return part[0] + '*' * (part.length - 1);
      if (i == parts.length - 1) {
        return '*' * (part.length - 1) + part[part.length - 1];
      }
      return '*' * part.length;
    }).join(' ');
  }

  /// Mirrors timeAgo — relative time string
  String _timeAgo(Timestamp ts, String justNowText) {
    final diff = DateTime.now().difference(ts.toDate());
    final mins = diff.inMinutes;
    if (mins < 1) return justNowText;
    if (mins < 60) return '${mins}m';
    final hours = diff.inHours;
    if (hours < 24) return '${hours}h';
    final days = diff.inDays;
    if (days < 30) return '${days}d';
    final months = (days / 30).floor();
    if (months < 12) return '${months}mo';
    final years = (months / 12).floor();
    return '${years}y';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final displayName = review.buyerName != null && review.buyerName!.isNotEmpty
        ? _maskName(review.buyerName!)
        : loc.anonymous;

    final timeText = review.timestamp != null
        ? _timeAgo(review.timestamp!, loc.foodReviewJustNow)
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]!.withOpacity(0.4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isDark ? Colors.grey[700]!.withOpacity(0.5) : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: avatar + name + time ──────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Stars ──────────────────────────────────────────────────────
          Row(
            children: List.generate(5, (i) {
              final filled = i < review.rating;
              return Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: filled
                      ? Colors.amber
                      : isDark
                          ? Colors.grey[700]
                          : Colors.grey[300],
                ),
              );
            }),
          ),

          // ── Comment ────────────────────────────────────────────────────
          // ── Comment ────────────────────────────────────────────────────
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
          ],

// ── Images ─────────────────────────────────────────────────────
          if (review.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final url = review.imageUrls[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ReviewImageViewer(url: url),
                      ),
                    ),
                    child: CloudinaryImage.fromUrl(
                      url: url,
                      // 2x the display size for crisp rendering on retina.
                      cdnWidth: 160,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      borderRadius: 8,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// REVIEW IMAGE VIEWER  —  fullscreen pinch-to-zoom image viewer
// =============================================================================

class _ReviewImageViewer extends StatelessWidget {
  final String url;
  const _ReviewImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // Cap at 1440 so huge-DPR devices don't request absurd sizes.
    final cdnWidth =
        (screenWidth * devicePixelRatio).clamp(720, 1440).round();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: CloudinaryImage.fromUrl(
            url: url,
            cdnWidth: cdnWidth,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LOAD MORE BUTTON  —  mirrors the hasMore footer button
// =============================================================================

class _LoadMoreButton extends StatelessWidget {
  final bool isLoadingMore;
  final bool isDark;
  final VoidCallback onTap;

  const _LoadMoreButton({
    required this.isLoadingMore,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return GestureDetector(
      onTap: isLoadingMore ? null : onTap,
      child: AnimatedOpacity(
        opacity: isLoadingMore ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoadingMore)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation(Colors.orange),
                    backgroundColor: Colors.orange.withOpacity(0.2),
                  ),
                )
              else
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              const SizedBox(width: 8),
              Text(
                isLoadingMore ? loc.foodReviewLoading : loc.foodReviewLoadMore,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// REVIEWS SKELETON  —  mirrors ReviewsSkeleton component
// =============================================================================

class _ReviewsSkeleton extends StatelessWidget {
  final bool isDark;
  const _ReviewsSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? Colors.grey[700]! : Colors.grey[200]!;
    final cardBg = isDark ? Colors.grey[800]!.withOpacity(0.4) : Colors.white;
    final cardBorder =
        isDark ? Colors.grey[700]!.withOpacity(0.5) : Colors.grey[200]!;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar + name row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration:
                        BoxDecoration(color: bg, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 13, width: 100, color: bg),
                      const SizedBox(height: 5),
                      Container(height: 10, width: 56, color: bg),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stars row
              Row(
                children: List.generate(
                  5,
                  (_) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Container(width: 14, height: 14, color: bg),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Comment lines
              Container(height: 12, width: double.infinity, color: bg),
              const SizedBox(height: 6),
              Container(
                  height: 12,
                  width: MediaQuery.of(context).size.width * 0.6,
                  color: bg),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// EMPTY STATE  —  mirrors empty reviews state
// =============================================================================

class _EmptyReviews extends StatelessWidget {
  final bool isDark;
  const _EmptyReviews({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 28,
              color: isDark ? Colors.grey[600] : Colors.grey[300],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            loc.foodReviewNoReviews,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.foodReviewBeFirst,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}
