import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/product_detail_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/REVIEWS-QUESTIONS/all_reviews_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/translation_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

class ProductDetailReviewsTab extends StatefulWidget {
  const ProductDetailReviewsTab({Key? key}) : super(key: key);

  @override
  _ProductDetailReviewsTabState createState() =>
      _ProductDetailReviewsTabState();
}

class _ProductDetailReviewsTabState extends State<ProductDetailReviewsTab> {
  Future<List<Map<String, dynamic>>>? _reviewsFuture;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);

    // Wait for collection to be determined
    if (!provider.collectionDetermined) {
      int attempts = 0;
      while (!provider.collectionDetermined && attempts < 50 && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
    }

    if (!mounted) return;

    final collectionName = provider.productCollection;
    if (collectionName == null) {
      debugPrint('⚠️ Could not determine product collection for reviews');
      return;
    }

    setState(() {
      _reviewsFuture =
          Provider.of<ProductDetailProvider>(context, listen: false)
              .getProductReviews(provider.productId, collectionName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    final product = provider.product;

    if (product == null || _reviewsFuture == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      behavior: HitTestBehavior.translucent,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reviewsFuture,
        builder: (context, snapshot) {
          // Don't show anything until we know if there are reviews
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState(context);
          }

          // Hide entire widget if no reviews
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }

          final reviews = snapshot.data!;

          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color.fromARGB(255, 40, 38, 59)
                  : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  spreadRadius: 0,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and See All button - always shown when reviews exist
                _ReviewsHeader(reviewCount: reviews.length),
                const SizedBox(height: 8),
                // Reviews list
                _ReviewsList(reviews: reviews),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final dimensions = _ReviewsList._getTileDimensions(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color.fromARGB(255, 40, 38, 59)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shimmer for title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 80,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 100,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Shimmer for reviews
          _ReviewsList._buildStaticShimmer(context, dimensions),
        ],
      ),
    );
  }
}

/// Simple header widget that shows title and "See All" button
class _ReviewsHeader extends StatelessWidget {
  final int reviewCount;

  const _ReviewsHeader({Key? key, required this.reviewCount}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.reviews,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ChangeNotifierProvider<ProductDetailProvider>.value(
                    value: provider,
                    child: AllReviewsScreen(productId: provider.productId),
                  ),
                ),
              );
            },
            child: Text(
              l10n.seeAllReviewsWithCount('($reviewCount)'),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;

  const _ReviewsList({Key? key, required this.reviews}) : super(key: key);

  /// Calculate responsive tile dimensions based on screen size
  static Map<String, double> _getTileDimensions(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final isLargeTablet = screenWidth > 900;

    // Responsive tile width
    double tileWidth;
    if (isLargeTablet) {
      tileWidth = 360.0;
    } else if (isTablet) {
      tileWidth = 320.0;
    } else {
      tileWidth = 280.0;
    }

    // Fixed tile height - must accommodate:
    // - Top row (~22px): stars + date + badge
    // - Padding (20px): 10px top + 10px bottom
    // - Spacing (10px): 6px + 4px
    // - Bottom row (20px): actions
    // - Content area: needs ~100px for 2 images (45px each + gap) + text
    // Total minimum: ~172px, use 180px for phones, 200px for tablets
    double tileHeight;
    if (isLargeTablet) {
      tileHeight = 210.0;
    } else if (isTablet) {
      tileHeight = 200.0;
    } else {
      tileHeight = 180.0;
    }

    return {'width': tileWidth, 'height': tileHeight};
  }

  /// Static shimmer builder for use during loading
  static Widget _buildStaticShimmer(BuildContext context, Map<String, double> dimensions) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode ? const Color(0xFF1C1A29) : Colors.grey[300]!;
    final highlightColor = isDarkMode ? const Color.fromARGB(255, 51, 48, 73) : Colors.grey[100]!;
    final tileWidth = dimensions['width']!;
    final tileHeight = dimensions['height']!;

    return SizedBox(
      height: tileHeight + 16.0,
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          itemCount: 3,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Container(
              width: tileWidth,
              height: tileHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = _getTileDimensions(context);
    final tileHeight = dimensions['height']!;

    return SizedBox(
      height: tileHeight + 16.0, // tile height + vertical margin
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        itemCount: reviews.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _ReviewTile(
              key: ValueKey(reviews[index]['reviewId']),
              review: reviews[index],
              tileDimensions: dimensions,
            ),
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  final Map<String, dynamic> review;
  final Map<String, double> tileDimensions;

  const _ReviewTile({
    Key? key,
    required this.review,
    required this.tileDimensions,
  }) : super(key: key);

  @override
  __ReviewTileState createState() => __ReviewTileState();
}

class __ReviewTileState extends State<_ReviewTile> {
  bool _isTranslated = false;
  String _translatedText = '';
  bool _isTranslating = false;
  bool _isLiked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    String? currentUserId = provider.currentUser?.uid;
    if (widget.review['likes'] != null && widget.review['likes'] is List) {
      List<dynamic> likes = widget.review['likes'];
      _likeCount = likes.length;
      if (currentUserId != null) {
        _isLiked = likes.contains(currentUserId);
      }
    } else {
      _likeCount = 0;
    }
  }

  @override
  void didUpdateWidget(covariant _ReviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.review['likes'] != widget.review['likes']) {
      _updateLikeStateFromFirestore();
    }
  }

  void _updateLikeStateFromFirestore() {
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    final currentUserId = provider.currentUser?.uid;
    final likes = (widget.review['likes'] is List)
        ? (widget.review['likes'] as List<dynamic>)
        : <dynamic>[];
    setState(() {
      _likeCount = likes.length;
      _isLiked = (currentUserId != null && likes.contains(currentUserId));
    });
  }

 Future<void> _translateReview(String originalText) async {
  setState(() {
    _isTranslating = true;
  });
  
  final userLocale = Localizations.localeOf(context).languageCode;
  final cacheKey = "translated_review_${widget.review['reviewId']}_$userLocale";
  
  try {
    // Check SharedPreferences cache first (persisted cache)
    final prefs = await SharedPreferences.getInstance();
    String? cachedTranslation = prefs.getString(cacheKey);
    
    if (cachedTranslation != null && cachedTranslation.isNotEmpty) {
      setState(() {
        _translatedText = cachedTranslation;
        _isTranslated = true;
        _isTranslating = false;
      });
      return;
    }
    
    // Use the new secure translation service
    final translationService = TranslationService();
    String translation = await translationService.translate(
      originalText,
      userLocale,
    );
    
    // Save to persistent cache
    await prefs.setString(cacheKey, translation);
    
    setState(() {
      _translatedText = translation;
      _isTranslated = true;
      _isTranslating = false;
    });
  } on RateLimitException catch (e) {
    setState(() {
      _isTranslating = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.retryAfter != null 
              ? 'Too many requests. Try again in ${e.retryAfter}s'
              : 'Translation limit reached. Try again later.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } on TranslationException catch (e) {
    setState(() {
      _isTranslating = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Translation failed: ${e.message}')),
      );
    }
  } catch (e) {
    setState(() {
      _isTranslating = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error translating review')),
      );
    }
  }
}

  void _resetTranslation() {
    setState(() {
      _isTranslated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rating = (widget.review['rating'] as num).toDouble();
    final reviewText = widget.review['review'] ?? '';
    final timestampValue = widget.review['timestamp'];
    final imageUrl = widget.review['imageUrl'] ?? '';

    List<String> imageUrls = [];
    if (widget.review['imageUrls'] != null &&
        widget.review['imageUrls'] is List) {
      imageUrls = List<String>.from(widget.review['imageUrls']);
    } else if (imageUrl.isNotEmpty) {
      imageUrls = [imageUrl];
    }

    // Handle both Timestamp and milliseconds (int) formats
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is int) {
      date = DateTime.fromMillisecondsSinceEpoch(timestampValue);
    } else {
      date = DateTime.now();
    }
    final l10n = AppLocalizations.of(context);
    final bool isLongReview = reviewText.length > 150;

    // Get dimensions from parent
    final tileWidth = widget.tileDimensions['width']!;
    final tileHeight = widget.tileDimensions['height']!;
    final isCompact = tileWidth < 300;

    // Calculate dynamic values based on content
    final bool hasImages = imageUrls.isNotEmpty;

    // Calculate available height for the Expanded content area
    // Total fixed heights: padding (20px) + top row (~22px) + spacings (10px) + bottom row (20px) = ~72px
    final double padding = isCompact ? 8.0 : 10.0;
    final double fixedHeight = (padding * 2) + 22 + 6 + 4 + 20; // ~72px
    final double availableContentHeight = tileHeight - fixedHeight;

    // Calculate image size to fit 2 images within available height
    // Each image + 4px gap between them
    final double maxImageSize = (availableContentHeight - 4) / 2;
    final double imageSize = maxImageSize.clamp(40.0, 55.0); // Clamp between 40-55px

    // Calculate max lines for review text based on available space
    final int maxLines = hasImages ? 3 : 4;

    return Container(
      width: tileWidth,
      height: tileHeight,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: EdgeInsets.all(isCompact ? 8.0 : 10.0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1C1A29)
            : const Color.fromARGB(255, 243, 243, 243),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row with star rating, date, and badge - always visible
          Row(
            children: [
              _buildStarRating(rating, isCompact),
              const SizedBox(width: 4.0),
              Text(
                _formatDate(date),
                style: TextStyle(
                  fontSize: isCompact ? 11 : 12,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 5.0 : 6.0,
                  vertical: 2.0,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color.fromARGB(255, 54, 50, 75)
                      : const Color.fromARGB(255, 214, 214, 214),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Text(
                  l10n.boughtThisProduct,
                  style: TextStyle(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                    fontSize: isCompact ? 9 : 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Expandable content area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Images on the left (if present)
                if (hasImages) ...[
                  _buildCompactImageColumn(context, imageUrls, imageSize),
                  const SizedBox(width: 8),
                ],
                // Review text takes remaining space
                Expanded(
                  child: Text(
                    _isTranslated ? _translatedText : reviewText,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 12 : 13,
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Bottom row: translation toggle, like, and "Read all" link - always visible
          SizedBox(
            height: 20,
            child: Row(
              children: [
                // Translate button
                GestureDetector(
                  onTap: _isTranslating
                      ? null
                      : _isTranslated
                          ? _resetTranslation
                          : () => _translateReview(reviewText),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language,
                        size: isCompact ? 12 : 14,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color.fromRGBO(0, 0, 0, 0.6),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _isTranslated ? l10n.seeOriginal : l10n.translate,
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color.fromRGBO(0, 0, 0, 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Like button
                GestureDetector(
                  onTap: _toggleLike,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLiked ? Icons.thumb_up : Icons.thumb_up_off_alt,
                        size: isCompact ? 12 : 14,
                        color: _isLiked
                            ? Colors.blue
                            : Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : const Color.fromRGBO(0, 0, 0, 0.6),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$_likeCount',
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color.fromRGBO(0, 0, 0, 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Loading indicator or Read all link
                if (_isTranslating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isLongReview)
                  GestureDetector(
                    onTap: () {
                      final detailProv = Provider.of<ProductDetailProvider>(
                          context,
                          listen: false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) =>
                              ChangeNotifierProvider<ProductDetailProvider>.value(
                            value: detailProv,
                            child: AllReviewsScreen(
                                productId: detailProv.productId),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      l10n.readAll,
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color.fromRGBO(0, 0, 0, 0.6),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactImageColumn(
      BuildContext context, List<String> imageUrls, double imageSize) {
    final int maxImages = imageUrls.length > 2 ? 2 : imageUrls.length;
    // Calculate total height: images + gaps
    final double totalHeight = (imageSize * maxImages) + (maxImages > 1 ? 4.0 : 0.0);

    return SizedBox(
      width: imageSize,
      height: totalHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(maxImages, (index) {
          return Padding(
            padding: EdgeInsets.only(bottom: index < maxImages - 1 ? 4.0 : 0.0),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullScreenImagePage(
                      imageUrl: imageUrls[index],
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: SizedBox(
                  width: imageSize,
                  height: imageSize,
                  child: CachedNetworkImage(
                    imageUrl: imageUrls[index],
                    placeholder: (context, url) => Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error, size: 14),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _toggleLike() async {
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    bool oldState = _isLiked;
    setState(() {
      _isLiked = !oldState;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount = _likeCount > 0 ? _likeCount - 1 : 0;
      }
    });
    await provider.toggleReviewLike(widget.review['reviewId'], oldState);
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}";
  }

  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  Widget _buildStarRating(double rating, bool isCompact) {
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;
    int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    final starSize = isCompact ? 12.0 : 14.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          Icon(FontAwesomeIcons.solidStar, color: Colors.amber, size: starSize),
        if (hasHalfStar)
          Icon(FontAwesomeIcons.starHalfStroke,
              color: Colors.amber, size: starSize),
        for (var i = 0; i < emptyStars; i++)
          Icon(FontAwesomeIcons.star, color: Colors.amber, size: starSize),
      ],
    );
  }

}

class FullScreenImagePage extends StatelessWidget {
  final String imageUrl;
  const FullScreenImagePage({Key? key, required this.imageUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Black background for full-screen view
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) =>
              const Icon(Icons.error, color: Colors.white),
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
