import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/product_card_4.dart';
import '../../providers/review_provider.dart';
import 'review_dialog.dart';
import '../../models/review_dialog_view_model.dart';
import 'package:go_router/go_router.dart';


class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({Key? key}) : super(key: key);

  @override
  _MyReviewsScreenState createState() => _MyReviewsScreenState();
}

enum ReviewFilter { all, product, seller }

class _MyReviewsScreenState extends State<MyReviewsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;
  static const Color jadeGreen = Color(0xFF00A86B);
  

  late TabController _tabController;
  late ScrollController _pendingController;
  late ScrollController _myController;

  ReviewFilter _filter = ReviewFilter.all;

  String? _currentProductFilter;
  String? _currentSellerFilter;
  DateTime? _currentStartDate;
  DateTime? _currentEndDate;

  // Pagination for "My Reviews"
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _myDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _myLastDoc;
  bool _myHasMore = true;
  bool _myLoading = false;
  bool _myInitialLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Instantiate TabController
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabController.index != 1) {
          setState(() {
            _filter = ReviewFilter.all;
          });
        }
      });

    _pendingController = ScrollController()..addListener(_pendingOnScroll);
    _myController = ScrollController()..addListener(_myOnScroll);

    // Load first page of "My Reviews"
    _fetchMyReviewPage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pendingController.dispose();
    _myController.dispose();
    super.dispose();
  }

  void _pendingOnScroll() {
    final provider = context.read<ReviewProvider>();
    if (_pendingController.position.pixels >=
            _pendingController.position.maxScrollExtent - 200 &&
        provider.canLoadMore) {
      provider.loadMore();
    }
  }

  void _myOnScroll() {
    if (_myController.position.pixels >=
            _myController.position.maxScrollExtent - 200 &&
        !_myLoading &&
        _myHasMore) {
      _fetchMyReviewPage();
    }
  }

  Future<void> _fetchMyReviewPage() async {
    if (!_myHasMore || _myLoading) return;
    setState(() => _myLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _myLoading = false);
        return;
      }

      // ✅ Build different queries based on filter type
      late Query<Map<String, dynamic>> q;

      switch (_filter) {
        case ReviewFilter.product:
          // Query only product/shop_product collections
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid)
              .where('productId',
                  isNotEqualTo: null); // Ensures it's a product review
          break;
        case ReviewFilter.seller:
          // Query only user/shop collections (seller reviews)
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid)
              .where('productId',
                  isEqualTo: null); // Ensures it's a seller-only review
          break;
        case ReviewFilter.all:
        default:
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid);
          break;
      }

      // Apply other filters
      if (_currentSellerFilter != null) {
        q = q.where('sellerId', isEqualTo: _currentSellerFilter);
      }

      if (_currentProductFilter != null) {
        q = q.where('productId', isEqualTo: _currentProductFilter);
      }

      if (_currentStartDate != null) {
        q = q.where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!),
        );
      }
      if (_currentEndDate != null) {
        final endOfDay = DateTime(_currentEndDate!.year, _currentEndDate!.month,
            _currentEndDate!.day, 23, 59, 59);
        q = q.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        );
      }

      // Order and paginate
      q = q.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_myLastDoc != null) {
        q = q.startAfterDocument(_myLastDoc!);
      }

      final snap = await q.get();
      final newDocs = snap.docs;

      if (newDocs.length < _pageSize) _myHasMore = false;
      if (newDocs.isNotEmpty) _myLastDoc = newDocs.last;

      if (mounted) {
        setState(() {
          _myDocs.addAll(newDocs);
          _myLoading = false;
          _myInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reviews: $e');
      if (mounted) {
        setState(() {
          _myLoading = false;
          _myInitialLoading = false;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final backgroundColor = isLight ? Colors.white : Colors.grey[900]!;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _currentStartDate != null && _currentEndDate != null
          ? DateTimeRange(start: _currentStartDate!, end: _currentEndDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: jadeGreen,
              onPrimary: Colors.white,
              surface: backgroundColor,
              onSurface: theme.colorScheme.onSurface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: isLight ? Colors.black : Colors.white,
              ),
            ), dialogTheme: DialogThemeData(backgroundColor: backgroundColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _currentStartDate = picked.start;
        _currentEndDate = picked.end;
        _myDocs.clear();
        _myLastDoc = null;
        _myHasMore = true;
        _myInitialLoading = true;
      });
      await _fetchMyReviewPage();
    }
  }

  Widget _buildReviewShimmerItem(bool isDark) {
    final baseColor = isDark
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDark
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
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
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 16,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 100,
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: baseColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => _buildReviewShimmerItem(isDark),
    );
  }

  // Modern loading modal
  void _showLoadingModal(AppLocalizations l10n) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 2 * 3.14159,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00A86B), Color(0xFF00C574)],
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.rate_review,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              l10n.submittingReview ?? 'Submitting review...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.pleaseWaitWhileWeProcessYourReview ?? 'Please wait while we process your review.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 8,
                width: double.infinity,
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 2),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF00A86B),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  // Success snackbar
  void _showSuccessSnackbar(AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(l10n.reviewSubmittedSuccessfully ??
                'Review submitted successfully!'),
          ],
        ),
        backgroundColor: jadeGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildModernTabBar() {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00A86B), Color(0xFF00C574)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00A86B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Theme.of(context).brightness == Brightness.light
            ? Colors.grey[600]
            : Colors.grey[400],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [
          _buildModernTab(l10n.toReview, Icons.rate_review),
          _buildModernTab(l10n.myRatings, Icons.star_rounded),
        ],
      ),
    );
  }

  Widget _buildModernTab(String text, IconData icon) {
    return Tab(
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final pending = context.watch<ReviewProvider>().pending;

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF1C1A29)
          : const Color.fromARGB(255, 235, 235, 235),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode ? null : Colors.white,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        title: Text(
          l10n.myReviews,
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range_rounded,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF1C1A29)
              : const Color.fromARGB(255, 233, 233, 233),
        ),
        child: SafeArea(
          bottom: true,
          child: Column(
            children: [
              _buildModernTabBar(),
              AnimatedBuilder(
                animation: _tabController.animation!,
                builder: (context, _) {
                  final animationValue = _tabController.animation!.value;
                  // Smooth fade in when moving to second tab
                  final opacity = animationValue.clamp(0.0, 1.0);

                  if (opacity == 0) {
                    return const SizedBox(height: 8);
                  }

                  const buttonWidth = 140.0;
                  final borderColor = isDarkMode
                      ? Colors.grey.shade600
                      : Colors.grey.shade500;

                  return Opacity(
                    opacity: opacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: buttonWidth,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: _filter == ReviewFilter.product
                                    ? Colors.orange
                                    : Colors.transparent,
                                side: BorderSide(
                                  color: _filter == ReviewFilter.product
                                      ? Colors.orange
                                      : borderColor,
                                  width: 1.2,
                                ),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                minimumSize: const Size(buttonWidth, 0),
                              ),
                              child: Text(
                                l10n.product,
                                style: TextStyle(
                                  color: _filter == ReviewFilter.product
                                      ? Colors.white
                                      : (isDarkMode ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onPressed: () => setState(() {
                                _filter = (_filter == ReviewFilter.product)
                                    ? ReviewFilter.all
                                    : ReviewFilter.product;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: buttonWidth,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: _filter == ReviewFilter.seller
                                    ? Colors.orange
                                    : Colors.transparent,
                                side: BorderSide(
                                  color: _filter == ReviewFilter.seller
                                      ? Colors.orange
                                      : borderColor,
                                  width: 1.2,
                                ),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                minimumSize: const Size(buttonWidth, 0),
                              ),
                              child: Text(
                                l10n.seller,
                                style: TextStyle(
                                  color: _filter == ReviewFilter.seller
                                      ? Colors.white
                                      : (isDarkMode ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onPressed: () => setState(() {
                                _filter = (_filter == ReviewFilter.seller)
                                    ? ReviewFilter.all
                                    : ReviewFilter.seller;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildPendingList(pending, isDarkMode, l10n),
                    _buildMyReviewsList(isDarkMode, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingList(List pending, bool isDark, AppLocalizations l10n) {
    if (pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/reviews.png', width: 140),
            const SizedBox(height: 12),
            Text(
              l10n.nothingToReview,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _pendingController,
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: pending.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final pr = pending[index];

        final data = pr.txDoc.data() as Map<String, dynamic>;
        final imageUrl = data['productImage'] as String? ?? '';
        final colorImages = <String, List<String>>{};
        final selectedColor = data['selectedColor'] as String?;
        if (selectedColor != null && imageUrl.isNotEmpty) {
          colorImages[selectedColor] = [imageUrl];
        }
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: () {
                    context.push('/product/${pr.productId}');
                  },
                  child: ProductCard4(
                    imageUrl: imageUrl,
                    colorImages: colorImages,
                    productName: data['productName'] as String,
                    brandModel: '',
                    price: (data['price'] as num).toDouble(),
                    currency: data['currency'] as String,
                    isShopProduct: pr.isShopProduct,
                    scaleFactor: 1.0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (!pr.productReviewed) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showReviewDialog(
                            context,
                            isProduct: true,
                            productId: pr.productId,
                            sellerId: pr.sellerId,
                            shopId: pr.shopId,
                            isShopProduct: pr.isShopProduct,
                            txId: pr.txDoc.id,
                            orderId: pr.orderId,
                          ),
                          icon: const Icon(Icons.rate_review, size: 18),
                          label: Text(
                            l10n.writeYourReview,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'Figtree',
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A86B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 12.0,
                            ),
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (!pr.sellerReviewed)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showReviewDialog(
                            context,
                            isProduct: false,
                            sellerId: pr.sellerId,
                            shopId: pr.shopId,
                            isShopProduct: pr.isShopProduct,
                            txId: pr.txDoc.id,
                            orderId: pr.orderId,
                          ),
                          icon: const Icon(Icons.store, size: 18),
                          label: Text(
                            pr.isShopProduct
                                ? l10n.shopReview
                                : l10n.sellerReview3,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'Figtree',
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF28C38),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 12.0,
                            ),
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyReviewsList(bool isDark, AppLocalizations l10n) {
    // Show shimmer for initial loading
    if (_myInitialLoading) {
      return _buildShimmerList(isDark);
    }

    final displayedDocs = _myDocs.where((doc) {
      final collectionId = doc.reference.parent.parent?.parent.id;
      switch (_filter) {
        case ReviewFilter.product:
          return collectionId == 'products' || collectionId == 'shop_products';
        case ReviewFilter.seller:
          return collectionId == 'users' || collectionId == 'shops';
        case ReviewFilter.all:
        default:
          return true;
      }
    }).toList();

    if (displayedDocs.isEmpty && !_myLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/reviews.png', width: 140),
            const SizedBox(height: 12),
            Text(
              l10n.youHaveNoReviews,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _myController,
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: displayedDocs.length + (_myLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index >= displayedDocs.length) {
          return _buildReviewShimmerItem(isDark);
        }
        final doc = displayedDocs[index];
        final data = doc.data();
        final collectionId = doc.reference.parent.parent?.parent.id;
        final parentDocRef = doc.reference.parent.parent!;
        final parentCollection = parentDocRef.parent.id;
        final imageUrl = data['productImage'] as String? ?? '';
        final productName = data['productName'] as String? ?? '';
        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
        final currency = data['currency'] as String? ?? '';
        final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final reviewText = data['review'] as String? ?? '';
        final imageUrls =
            (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        final parentFolder = doc.reference.parent.parent!;
        final parentId = parentDocRef.id;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (collectionId == 'users' || collectionId == 'shops') ...[
                  GestureDetector(
                    onTap: () {
                      if (parentCollection == 'shops') {
                        context.push('/shop_detail/$parentId');
                      } else {
                        context.push('/user_profile/$parentId');
                      }
                    },
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${l10n.sellerReview3}: ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                          TextSpan(
                            text: data['sellerName'] as String? ??
                                'Unknown Seller',
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  GestureDetector(
                    onTap: () =>
                        context.push('/product/${data['productId']}'),
                    child: ProductCard4(
                      imageUrl: imageUrl,
                      colorImages: const {},
                      productName: productName,
                      brandModel: '',
                      price: price,
                      currency: currency,
                      averageRating: rating,
                      showOverlayIcons: false,
                      isShopProduct: false,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1C1A29)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrls.isNotEmpty) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: imageUrls
                                .map((url) => Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.of(context)
                                              .push(MaterialPageRoute(
                                            builder: (_) => Scaffold(
                                              backgroundColor: Colors.black,
                                              appBar: AppBar(
                                                backgroundColor:
                                                    Colors.transparent,
                                                elevation: 0,
                                                leading: const BackButton(
                                                    color: Colors.white),
                                              ),
                                              body: Center(
                                                child: InteractiveViewer(
                                                  child: Image.network(url),
                                                ),
                                              ),
                                            ),
                                          ));
                                        },
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Image.network(
                                            url,
                                            height: 60,
                                            width: 60,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        reviewText,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),                
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showReviewDialog(
    BuildContext context, {
    required bool isProduct,
    String? productId,
    String? sellerId,
    String? shopId,
    bool isShopProduct = false,
    required String txId,
    required String orderId,
  }) async {
    final l10n = AppLocalizations.of(context);
    final storage = FirebaseStorage.instance;
    final collectionPath = isProduct
        ? (isShopProduct
            ? 'shop_products/$productId/reviews'
            : 'products/$productId/reviews')
        : (shopId != null
            ? 'shops/$shopId/reviews'
            : 'users/$sellerId/reviews');
    final docId = txId;

    try {
      final existing = await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(docId)
          .get();
      if (existing.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reviewAlreadyExists)),
        );
        return;
      }      

      // Create the view model instance
      final viewModel = ReviewDialogViewModel(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
        storage: storage,
        orderId: orderId,        
      );

      final result = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (ctx) => ReviewDialog(
          l10n: l10n,
          isProduct: isProduct,
          isShopProduct: isShopProduct,
          productId: productId,
          sellerId: sellerId,
          shopId: shopId,
          transactionId: txId,
          orderId: orderId,
          collectionPath: collectionPath,
          docId: docId,
          storagePath: isProduct
              ? 'reviews/$productId'
              : 'review_images/${FirebaseAuth.instance.currentUser!.uid}',
          isDarkMode: Theme.of(context).brightness == Brightness.dark,
          viewModel: viewModel,
          parentContext: context,
          onReviewSubmitted: () async {
            // This callback is called when the dialog closes
            // Now show loading modal and submit the review
            if (mounted) {
              _showLoadingModal(l10n);

              // Submit the review asynchronously
              await viewModel.submitReview(
                collectionPath: collectionPath,
                docId: docId,
                isProduct: isProduct,
                isShopProduct: isShopProduct,
                transactionId: txId,
                productId: productId,
                sellerId: sellerId ?? '',
                shopId: shopId,
                storagePath: isProduct
                    ? 'reviews/$productId'
                    : 'review_images/${FirebaseAuth.instance.currentUser!.uid}',
                orderId: orderId,
                context: context,
                onSuccess: () {
                  if (mounted) {
                    Navigator.of(context).pop(); // Close loading modal
                    _showSuccessSnackbar(l10n);

                    // Refresh the pending reviews
                    final reviewProvider = context.read<ReviewProvider>();
                    reviewProvider.loadPendingReviews(
                        FirebaseAuth.instance.currentUser!.uid);
                  }
                },
                onError: (error) {
                  if (mounted) {
                    Navigator.of(context).pop(); // Close loading modal
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $error'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              );
            }
          },
        ),
      );

      // Note: We don't need to handle the result here anymore since
      // the submission is handled in the onReviewSubmitted callback
    } catch (e) {
      debugPrint('Error showing review dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
}
