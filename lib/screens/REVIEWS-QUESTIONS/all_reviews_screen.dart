// lib/screens/all_reviews_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../services/translation_service.dart';
import '../../providers/product_detail_provider.dart';

/// Static cache for all reviews
class _AllReviewsCache {
  static final Map<String, List<Map<String, dynamic>>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const int _maxCacheSize = 30;
  static const Duration _cacheTTL = Duration(minutes: 5);

  static Future<List<Map<String, dynamic>>> getAllReviews(
    String productId,
    String collectionName,
  ) async {
    final now = DateTime.now();

    // Check cache
    if (_cache.containsKey(productId) && _cacheTimestamps.containsKey(productId)) {
      final cacheTime = _cacheTimestamps[productId]!;
      if (now.difference(cacheTime) < _cacheTTL) {
        return _cache[productId]!;
      }
      // Expired
      _cache.remove(productId);
      _cacheTimestamps.remove(productId);
    }

    // Fetch all reviews from Firestore
    final snapshot = await FirebaseFirestore.instance
        .collection(collectionName)
        .doc(productId)
        .collection('reviews')
        .orderBy('timestamp', descending: true)
        .get();

    final reviews = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['reviewId'] = doc.id;
      return data;
    }).toList();

    // Store in cache
    _cache[productId] = reviews;
    _cacheTimestamps[productId] = now;

    // Evict oldest if full
    if (_cache.length > _maxCacheSize) {
      final sortedEntries = _cacheTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final toRemove = sortedEntries.take(_cache.length - _maxCacheSize);
      for (final entry in toRemove) {
        _cache.remove(entry.key);
        _cacheTimestamps.remove(entry.key);
      }
    }

    return reviews;
  }
}

class AllReviewsScreen extends StatefulWidget {
  final String productId;

  const AllReviewsScreen({
    Key? key,
    required this.productId,
  }) : super(key: key);

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
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
      debugPrint('⚠️ Could not determine product collection for all reviews');
      return;
    }

    setState(() {
      _reviewsFuture = _AllReviewsCache.getAllReviews(widget.productId, collectionName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.allReviews,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        top: false, // AppBar already handles top safe area
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _reviewsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noReviewsYet,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              }
              final reviews = snapshot.data!;
              return ListView.builder(
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 8.0,
                  bottom: 8.0 + MediaQuery.of(context).padding.bottom,
                ),
                itemCount: reviews.length,
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return _ReviewTile(
                    key: ValueKey(review['reviewId']),
                    review: review,
                    productId: widget.productId,
                    reviewId: review['reviewId'],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  final Map<String, dynamic> review;
  final String productId;
  final String reviewId;

  const _ReviewTile({
    Key? key,
    required this.review,
    required this.productId,
    required this.reviewId,
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
    // Use FirebaseAuth directly to determine the current user's like status.
    final currentUser = FirebaseAuth.instance.currentUser;
    if (widget.review['likes'] != null && widget.review['likes'] is List) {
      List<dynamic> likes = widget.review['likes'];
      _likeCount = likes.length;
      if (currentUser != null) {
        _isLiked = likes.contains(currentUser.uid);
      }
    } else {
      _likeCount = 0;
    }
  }

  // NEW: Re-check likes whenever a new snapshot arrives (e.g. if 'likes' changed).
  @override
  void didUpdateWidget(covariant _ReviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.review['likes'] != widget.review['likes']) {
      _updateLikeStateFromFirestore();
    }
  }

  // NEW: Helper to update _isLiked and _likeCount from Firestore data.
  void _updateLikeStateFromFirestore() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final likes = (widget.review['likes'] is List)
        ? (widget.review['likes'] as List<dynamic>)
        : <dynamic>[];
    setState(() {
      _likeCount = likes.length;
      _isLiked = currentUser != null && likes.contains(currentUser.uid);
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

    // ✅ FIX: Handle both Timestamp and milliseconds (int) formats
    DateTime date;
    if (timestampValue is Timestamp) {
      date = timestampValue.toDate();
    } else if (timestampValue is int) {
      date = DateTime.fromMillisecondsSinceEpoch(timestampValue);
    } else {
      date = DateTime.now();
    }
    final l10n = AppLocalizations.of(context);
    bool isLongReview = reviewText.length > 150;

    // Determine color for icons and texts based on dark mode.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconTextColor =
        isDark ? Colors.white : const Color.fromRGBO(0, 0, 0, 0.6);

    return Container(
      // Uses nearly full width with margins from the ListView's padding.
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color.fromARGB(255, 39, 36, 57) // Dark mode background
            : const Color.fromARGB(255, 243, 243, 243), // Light mode background
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Star rating, date, and "Bought this product" badge.
          Row(
            children: [
              _buildStarRating(rating),
              const SizedBox(width: 4.0),
              Text(
                _formatDate(date),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
              ),
              const SizedBox(width: 8.0),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color.fromARGB(
                          255, 54, 50, 75) // Dark mode background
                      : const Color.fromARGB(
                          255, 214, 214, 214), // Light mode background
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Text(
                  l10n.boughtThisProduct,
                  style: const TextStyle(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (imageUrls.isNotEmpty) _buildImageRow(context, imageUrls),
          const SizedBox(height: 8),
          // Display the full review text (no maxLines limit)
          Text(
            _isTranslated ? _translatedText : reviewText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          // Bottom row: Translate icon/text, like icon with count.
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
  onTap: _isTranslating
      ? null
      : () => _translateReview(reviewText),
  child: Icon(
    _isTranslated ? Icons.language_outlined : Icons.language,
    size: 14,
    color: iconTextColor,
  ),
),
const SizedBox(width: 4),
GestureDetector(
  onTap: _isTranslating
      ? null
      : () => _translateReview(reviewText),
  child: Text(
    _isTranslated ? l10n.seeOriginal : l10n.translate, // You may need to add 'original' to l10n
    style: TextStyle(
      color: iconTextColor,
    ),
  ),
),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleLike,
                    child: Icon(
                      _isLiked ? Icons.thumb_up : Icons.thumb_up_off_alt,
                      size: 16,
                      color: _isLiked ? Colors.blue : iconTextColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_likeCount',
                    style: TextStyle(
                      fontSize: 14,
                      color: iconTextColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_isTranslating)
  Padding(
    padding: const EdgeInsets.only(left: 8.0),
    child: SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          isDark ? Colors.white : Colors.black87,
        ),
      ),
    ),
  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(double rating) {
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;
    int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          const Icon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 14),
        if (hasHalfStar)
          const Icon(FontAwesomeIcons.starHalfStroke,
              color: Colors.amber, size: 14),
        for (var i = 0; i < emptyStars; i++)
          const Icon(FontAwesomeIcons.star, color: Colors.amber, size: 14),
      ],
    );
  }

  Widget _buildImageRow(BuildContext context, List<String> imageUrls) {
    int maxImages = imageUrls.length > 3 ? 3 : imageUrls.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(maxImages, (index) {
        return Padding(
          padding: EdgeInsets.only(right: index < maxImages - 1 ? 4.0 : 0.0),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FullScreenImagePage(imageUrl: imageUrls[index]),
                ),
              );
            },
            child: SizedBox(
              width: 80,
              height: 80,
              child: CachedNetworkImage(
                imageUrl: imageUrls[index],
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      }),
    );
  }

 Future<void> _translateReview(String originalText) async {
  if (_isTranslated) {
    setState(() {
      _isTranslated = false;
    });
    return;
  }

  final userLocale = Localizations.localeOf(context).languageCode;
  final translationService = TranslationService();

  // Check cache first
  final cachedTranslation = translationService.getCached(originalText, userLocale);
  if (cachedTranslation != null) {
    setState(() {
      _translatedText = cachedTranslation;
      _isTranslated = true;
    });
    return;
  }

  setState(() {
    _isTranslating = true;
  });

  try {
    final translation = await translationService.translate(
      originalText,
      userLocale,
    );

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
              : 'Translation limit reached.'),
        ),
      );
    }
  } catch (e) {
    setState(() {
      _isTranslating = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error translating review: $e')),
      );
    }
  }
}

  Future<void> _toggleLike() async {
    // Optimistically update the UI.
    bool oldState = _isLiked;
    setState(() {
      _isLiked = !oldState;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount = _likeCount > 0 ? _likeCount - 1 : 0;
      }
    });
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    await provider.toggleReviewLike(widget.reviewId, oldState);
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}";
  }

  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }
}

class FullScreenImagePage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImagePage({Key? key, required this.imageUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Full-screen image view background
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
