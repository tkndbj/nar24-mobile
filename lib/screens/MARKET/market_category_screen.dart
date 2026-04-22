// lib/screens/market/market_category_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/cloudinary_image.dart';

const Map<String, String> _kCategoryAssetBySlug = {
  'alcohol-cigarette': 'assets/images/market-items/cigaretteandalcohol.png',
  'snack': 'assets/images/market-items/snacks.png',
  'drinks': 'assets/images/market-items/drinks.png',
  'water': 'assets/images/market-items/water.png',
  'fruit-vegetables': 'assets/images/market-items/vegetablesandfruit.png',
  'food': 'assets/images/market-items/food.png',
  'meat-chicken-fish': 'assets/images/market-items/meat.png',
  'basic-food': 'assets/images/market-items/basicfood.png',
  'dairy-breakfast': 'assets/images/market-items/dairyandbreakfast.png',
  'bakery': 'assets/images/market-items/bakery.png',
  'ice-cream': 'assets/images/market-items/icecream.png',
  'fit-form': 'assets/images/market-items/fitandform.png',
  'home-care': 'assets/images/market-items/homecare.png',
  'home-lite': 'assets/images/market-items/homelite.png',
  'personal-care': 'assets/images/market-items/personalcare.png',
  'technology': 'assets/images/market-items/technology.png',
  'sexual-health': 'assets/images/market-items/sexualhealth.png',
  'baby': 'assets/images/market-items/baby.png',
  'clothing': 'assets/images/market-items/clothing.png',
  'stationery': 'assets/images/market-items/stationery.png',
  'pet': 'assets/images/market-items/pets.png',
  'tools': 'assets/images/market-items/tools.png',
};

// ============================================================================
// SCREEN
// ============================================================================

class MarketCategoryScreen extends StatefulWidget {
  const MarketCategoryScreen({super.key});

  @override
  State<MarketCategoryScreen> createState() => _MarketCategoryScreenState();
}

class _MarketCategoryScreenState extends State<MarketCategoryScreen>
    with SingleTickerProviderStateMixin {
  static const _kSearchAnimDuration = Duration(milliseconds: 260);

  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnim;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: _kSearchAnimDuration,
    );
    _searchAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    setState(() => _searchOpen = true);
    // Forward animation first; request focus after the frame so the field
    // is mounted and focusable.
    await _searchAnimCtrl.forward();
    if (!mounted) return;
    _searchFocus.requestFocus();
  }

  Future<void> _closeSearch() async {
    if (!_searchOpen) return;
    _searchFocus.unfocus();
    await _searchAnimCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _searchOpen = false;
      _searchController.clear();
    });
  }

  void _submitSearch(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _searchFocus.unfocus();
    context.push('/market-search?q=${Uri.encodeQueryComponent(trimmed)}');
  }

  void _openReviewsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => const _MarketReviewsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 0,
        title: AnimatedBuilder(
          animation: _searchAnim,
          builder: (context, _) {
            final t = _searchAnim.value;
            return SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.centerLeft,
                fit: StackFit.expand,
                children: [
                  // Title (fades out as search opens)
                  IgnorePointer(
                    ignoring: _searchOpen,
                    child: Opacity(
                      opacity: 1 - t,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.marketCategoryTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Search field (fades/slides in). Mount only when opening.
                  if (_searchOpen)
                    Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(12 * (1 - t), 0),
                        child: _AppBarSearchField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          hintText: l10n.marketSearchHint,
                          onSubmitted: _submitSearch,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_searchOpen ? Icons.arrow_back : Icons.arrow_back),
          onPressed: () {
            if (_searchOpen) {
              _closeSearch();
            } else {
              context.canPop() ? context.pop() : context.go('/');
            }
          },
        ),
        actions: [
          AnimatedBuilder(
            animation: _searchAnim,
            builder: (context, _) {
              final showClose = _searchAnim.value > 0.5;
              return IconButton(
                icon: Icon(showClose ? Icons.close : Icons.search),
                onPressed: _searchOpen ? _closeSearch : _openSearch,
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.marketCategoriesHeader,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.marketCategoriesCount(
                                kMarketCategories.length),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ReviewsChip(
                      label: l10n.marketReviewsLabel,
                      isDark: isDark,
                      onTap: () => _openReviewsSheet(context),
                    ),
                  ],
                ),
              ),
            ),

            // ── Category grid ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final cat = kMarketCategories[index];
                    return _CategoryTile(
                      category: cat,
                      isDark: isDark,
                      onTap: () => context.push(
                        '/market-category/${cat.slug}',
                      ),
                    );
                  },
                  childCount: kMarketCategories.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        ),
      ),
    );
  }
}

// ============================================================================
// APPBAR SEARCH FIELD
// ============================================================================

class _AppBarSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  const _AppBarSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        cursorColor: Colors.white,
        cursorHeight: 22,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 15,
          ),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

// ============================================================================
// CATEGORY TILE
// ============================================================================

class _CategoryTile extends StatelessWidget {
  final MarketCategory category;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: category.color.withOpacity(isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _kCategoryAssetBySlug[category.slug] != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        _kCategoryAssetBySlug[category.slug]!,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Text(category.emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                category.localizedLabel(l10n),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// REVIEWS CHIP (header action)
// ============================================================================

class _ReviewsChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _ReviewsChip({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF00A86B).withOpacity(0.18)
                : const Color(0xFF00A86B).withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00A86B).withOpacity(0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF007A4D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MARKET REVIEWS BOTTOM SHEET
// ============================================================================

class _MarketReviewsSheet extends StatelessWidget {
  const _MarketReviewsSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1A29) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.marketReviewsSheetTitle,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.grey[800] : Colors.grey[200],
              ),
              Expanded(
                child: _MarketReviewsList(
                  scrollController: scrollController,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// MARKET REVIEW MODEL (mirrors functions/52-market-payment/index.js schema)
// ============================================================================

class _MarketReview {
  final String id;
  final String buyerName;
  final int rating;
  final String comment;
  final List<String> imageUrls;
  final Timestamp? timestamp;

  const _MarketReview({
    required this.id,
    required this.buyerName,
    required this.rating,
    required this.comment,
    required this.imageUrls,
    this.timestamp,
  });

  factory _MarketReview.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return _MarketReview(
      id: doc.id,
      buyerName: (d['buyerName'] as String?) ?? '',
      rating: (d['rating'] as num?)?.toInt() ?? 0,
      comment: (d['comment'] as String?) ?? '',
      imageUrls: (d['imageUrls'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      timestamp: d['timestamp'] as Timestamp?,
    );
  }
}

// ============================================================================
// PAGINATED REVIEWS LIST (cursor-based, infinite scroll, page size 15)
// ============================================================================

class _MarketReviewsList extends StatefulWidget {
  final ScrollController scrollController;
  final bool isDark;

  const _MarketReviewsList({
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<_MarketReviewsList> createState() => _MarketReviewsListState();
}

class _MarketReviewsListState extends State<_MarketReviewsList> {
  static const int _kPageSize = 15;
  static const double _kLoadMoreThreshold = 300;

  final List<_MarketReview> _reviews = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _kLoadMoreThreshold) {
      _fetchPage(reset: false);
    }
  }

  Future<void> _fetchPage({required bool reset}) async {
    if (!reset) {
      if (_isLoadingMore || !_hasMore || _isLoading) return;
    }

    if (mounted) {
      setState(() {
        if (reset) {
          _isLoading = true;
          _hasError = false;
          _hasMore = true;
          _lastDoc = null;
          _reviews.clear();
        } else {
          _isLoadingMore = true;
        }
      });
    }

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('nar24market')
          .doc('stats')
          .collection('reviews')
          .orderBy('timestamp', descending: true)
          .limit(_kPageSize);

      if (!reset && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }

      final snapshot = await q.get();
      final fetched =
          snapshot.docs.map(_MarketReview.fromDoc).toList(growable: false);

      if (!mounted) return;
      setState(() {
        if (snapshot.docs.isNotEmpty) {
          _lastDoc = snapshot.docs.last;
        }
        _hasMore = snapshot.docs.length == _kPageSize;
        _reviews.addAll(fetched);
      });
    } catch (e) {
      debugPrint('[MarketReviewsList] Fetch error: $e');
      if (!mounted) return;
      setState(() => _hasError = true);
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
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF00A86B)),
          ),
        ),
      );
    }

    if (_hasError && _reviews.isEmpty) {
      return _ReviewsErrorState(
        isDark: widget.isDark,
        message: l10n.marketReviewsErrorLoad,
        retryLabel: l10n.marketOrdersTryAgain,
        onRetry: () => _fetchPage(reset: true),
      );
    }

    if (_reviews.isEmpty) {
      return _ReviewsEmptyState(
        isDark: widget.isDark,
        title: l10n.marketReviewsEmptyTitle,
        subtitle: l10n.marketReviewsEmptySubtitle,
      );
    }

    final itemCount = _reviews.length + (_hasMore || _isLoadingMore ? 1 : 0);

    return ListView.separated(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _reviews.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00A86B)),
                  backgroundColor:
                      const Color(0xFF00A86B).withOpacity(0.15),
                ),
              ),
            ),
          );
        }
        return _MarketReviewCard(
          review: _reviews[index],
          isDark: widget.isDark,
        );
      },
    );
  }
}

// ============================================================================
// REVIEW CARD
// ============================================================================

class _MarketReviewCard extends StatelessWidget {
  final _MarketReview review;
  final bool isDark;

  const _MarketReviewCard({required this.review, required this.isDark});

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

  String _timeAgo(Timestamp ts) {
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo';
    return '${(months / 12).floor()}y';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = review.buyerName.isNotEmpty
        ? _maskName(review.buyerName)
        : AppLocalizations.of(context)!.anonymous;
    final timeText =
        review.timestamp != null ? _timeAgo(review.timestamp!) : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final filled = i < review.rating;
                  return Padding(
                    padding: const EdgeInsets.only(left: 1),
                    child: Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: filled
                          ? Colors.amber
                          : (isDark ? Colors.grey[700] : Colors.grey[300]),
                    ),
                  );
                }),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ],
          if (review.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return CloudinaryImage.fromUrl(
                    url: review.imageUrls[i],
                    cdnWidth: 160,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    borderRadius: 8,
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

// ============================================================================
// EMPTY + ERROR STATES
// ============================================================================

class _ReviewsEmptyState extends StatelessWidget {
  final bool isDark;
  final String title;
  final String subtitle;

  const _ReviewsEmptyState({
    required this.isDark,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewsErrorState extends StatelessWidget {
  final bool isDark;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const _ReviewsErrorState({
    required this.isDark,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00A86B),
                side: const BorderSide(color: Color(0xFF00A86B)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
