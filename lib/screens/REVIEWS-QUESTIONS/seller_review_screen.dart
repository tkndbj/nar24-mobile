import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/translation_service.dart';
import 'package:go_router/go_router.dart';

class SellerReviewScreen extends StatefulWidget {
  final String sellerId;

  const SellerReviewScreen({Key? key, required this.sellerId})
      : super(key: key);

  @override
  _SellerReviewScreenState createState() => _SellerReviewScreenState();
}

class _SellerReviewScreenState extends State<SellerReviewScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _sellerName = '';
  List<Map<String, dynamic>> _reviews = [];
  double _averageRating = 0.0;
  int _totalReviews = 0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSellerInfo();
    _fetchSellerReviews();
  }

  Future<void> _fetchSellerInfo() async {
    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(widget.sellerId).get();

    if (userDoc.exists) {
      String sellerName = userDoc['displayName'] ?? 'Seller';
      setState(() {
        _sellerName = sellerName;
      });
    } else {
      setState(() {
        _sellerName = 'Seller';
      });
    }
  }

  Future<void> _fetchSellerReviews() async {
    QuerySnapshot snapshot = await _firestore
        .collection('users')
        .doc(widget.sellerId)
        .collection('reviews')
        .get();

    List<Map<String, dynamic>> reviews = [];
    double totalRating = 0.0;

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      data['reviewId'] = doc.id;
      reviews.add(data);
      totalRating += (data['rating'] as num).toDouble();
    }

    int totalReviews = reviews.length;
    double averageRating = totalReviews > 0 ? totalRating / totalReviews : 0.0;

    setState(() {
      _reviews = reviews;
      _totalReviews = totalReviews;
      _averageRating = averageRating;
      isLoading = false;
    });
  }

  void _showReportOptions() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.report,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildReportOption(
                  context,
                  Icons.inventory_2_outlined,
                  l10n.inappropriateProducts,
                  'inappropriate_products',
                ),
                _buildReportOption(
                  context,
                  Icons.person_outline,
                  l10n.inappropriateName,
                  'inappropriate_name',
                ),
                _buildReportOption(
                  context,
                  Icons.info_outline,
                  l10n.inappropriateProductInformation,
                  'inappropriate_product_information',
                ),
                _buildReportOption(
                  context,
                  Icons.local_shipping_outlined,
                  l10n.unsuccessfulDelivery,
                  'unsuccessful_delivery',
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportOption(
      BuildContext context, IconData icon, String title, String reportType) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _submitReport(reportType);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _submitReport(String reportType) async {
    final l10n = AppLocalizations.of(context);
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pleaseLogin),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await _firestore
          .collection('users')
          .doc(widget.sellerId)
          .collection('reports')
          .add({
        'reporterId': currentUser.uid,
        'reportType': reportType,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.reportSubmittedSuccessfully),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error submitting report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.errorSubmittingReport),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 200,
                  floating: false,
                  pinned: true,
                  elevation: 0,
                  backgroundColor:
                      isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  leading: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey[200],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.person_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      onPressed: () {
                        context.push('/user_profile/${widget.sellerId}');
                      },
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.report_outlined,
                          size: 20,
                          color: Colors.red,
                        ),
                      ),
                      onPressed: _showReportOptions,
                    ),
                    const SizedBox(width: 8),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDarkMode
                              ? [
                                  const Color(0xFF1E1E1E),
                                  const Color(0xFF2D2D2D),
                                ]
                              : [
                                  Colors.white,
                                  Colors.grey[50]!,
                                ],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const SizedBox(height: 60),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF11998e),
                                  width: 3,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 35,
                                backgroundColor:
                                    const Color(0xFF11998e).withOpacity(0.2),
                                child: Text(
                                  _sellerName.isNotEmpty
                                      ? _sellerName[0].toUpperCase()
                                      : 'S',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF11998e),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _sellerName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF11998e),
                                    Color(0xFF38ef7d)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Verified Seller',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      // Rating Card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF11998e).withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _averageRating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0;
                                      i < _averageRating.floor();
                                      i++)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 1.5),
                                      child: Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 16,
                                      ),
                                    ),
                                  if ((_averageRating -
                                          _averageRating.floor()) >=
                                      0.5)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 1.5),
                                      child: Icon(
                                        Icons.star_half,
                                        color: Colors.amber,
                                        size: 16,
                                      ),
                                    ),
                                  for (var i = 0;
                                      i <
                                          5 -
                                              _averageRating.floor() -
                                              (((_averageRating -
                                                          _averageRating
                                                              .floor()) >=
                                                      0.5)
                                                  ? 1
                                                  : 0);
                                      i++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 1.5),
                                      child: Icon(
                                        Icons.star_border,
                                        color: Colors.white.withOpacity(0.5),
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${l10n.reviews} • $_totalReviews',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Reviews Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Text(
                              l10n.allReviews,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$_totalReviews',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                if (_reviews.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.rate_review_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.noReviewsYet,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _ReviewTile(
                            review: _reviews[index],
                            sellerId: widget.sellerId,
                          );
                        },
                        childCount: _reviews.length,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 32),
                ),
              ],
            ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  final Map<String, dynamic> review;
  final String sellerId;

  const _ReviewTile({Key? key, required this.review, required this.sellerId})
      : super(key: key);

  @override
  _ReviewTileState createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  bool _isTranslated = false;
  String _translatedText = '';
  bool _isTranslating = false;
  bool _isLiked = false;
  int _likeCount = 0;
  late String _originalReviewText;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _originalReviewText = widget.review['review'] ?? '';
    _updateLikeStateFromFirestore();
  }

  void _updateLikeStateFromFirestore() {
    final currentUserId = _auth.currentUser?.uid;
    final likes = (widget.review['likes'] is List)
        ? (widget.review['likes'] as List<dynamic>)
        : <dynamic>[];
    _likeCount = likes.length;
    _isLiked = (currentUserId != null && likes.contains(currentUserId));
  }

  Future<void> _toggleLike() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to like reviews.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reviewId = widget.review['reviewId'];
    final reviewDocRef = _firestore
        .collection('users')
        .doc(widget.sellerId)
        .collection('reviews')
        .doc(reviewId);

    bool oldState = _isLiked;
    setState(() {
      _isLiked = !oldState;
      if (_isLiked) {
        _likeCount++;
      } else {
        _likeCount = _likeCount > 0 ? _likeCount - 1 : 0;
      }
    });

    try {
      if (oldState) {
        await reviewDocRef.update({
          'likes': FieldValue.arrayRemove([currentUserId])
        });
      } else {
        await reviewDocRef.update({
          'likes': FieldValue.arrayUnion([currentUserId])
        });
      }
      DocumentSnapshot updatedReview = await reviewDocRef.get();
      if (updatedReview.exists) {
        setState(() {
          widget.review['likes'] =
              (updatedReview.data() as Map<String, dynamic>)['likes'] ?? [];
          _updateLikeStateFromFirestore();
        });
      }
    } catch (e) {
      setState(() {
        _isLiked = oldState;
        _likeCount = oldState ? _likeCount + 1 : _likeCount - 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error toggling like: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleTranslation() async {
  if (_isTranslated) {
    setState(() {
      _isTranslated = false;
    });
    return;
  }

  final userLocale = Localizations.localeOf(context).languageCode;
  final translationService = TranslationService();

  // Check cache first
  final cachedTranslation = translationService.getCached(_originalReviewText, userLocale);
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
      _originalReviewText,
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
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    setState(() {
      _isTranslating = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error translating review: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

  Widget _buildStarRating(double rating) {
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;
    int emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(Icons.star, color: Colors.amber, size: 16),
          ),
        if (hasHalfStar)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(Icons.star_half, color: Colors.amber, size: 16),
          ),
        for (var i = 0; i < emptyStars; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star_border, color: Colors.grey[400], size: 16),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return "${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}";
  }

  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    double rating = (widget.review['rating'] as num).toDouble();
    final timestampValue = widget.review['timestamp'];

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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStarRating(rating),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDate(date),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _isTranslated ? _translatedText : _originalReviewText,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  onTap: _toggleTranslation,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.translate,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isTranslated ? l10n.seeOriginal : l10n.translate,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _toggleLike,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isLiked
                          ? const Color(0xFF11998e).withOpacity(0.1)
                          : isDarkMode
                              ? Colors.white.withOpacity(0.05)
                              : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: _isLiked
                          ? Border.all(
                              color: const Color(0xFF11998e).withOpacity(0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                          size: 16,
                          color: _isLiked
                              ? const Color(0xFF11998e)
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_likeCount',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isLiked
                                ? const Color(0xFF11998e)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_isTranslating)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
