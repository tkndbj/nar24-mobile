import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/product_card_4.dart';
import 'package:go_router/go_router.dart';
import '../FILTER-SCREENS/seller_panel_reviews_filter_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class SellerPanelReviewsScreen extends StatefulWidget {
  final String shopId;
  const SellerPanelReviewsScreen({Key? key, required this.shopId})
      : super(key: key);

  @override
  _SellerPanelReviewsScreenState createState() =>
      _SellerPanelReviewsScreenState();
}

class _SellerPanelReviewsScreenState extends State<SellerPanelReviewsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;

  late TabController _tabController;
  late ScrollController _prodController;
  late ScrollController _shopController;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _prodDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _prodLastDoc;
  bool _prodHasMore = true;
  bool _prodLoading = false;
  static const Color jadeGreen = Color(0xFF00A86B);

  String? _currentProductFilter;
  DateTime? _currentStartDate;
  DateTime? _currentEndDate;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _shopDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _shopLastDoc;
  bool _shopHasMore = true;
  bool _shopLoading = false;

  // Initial load tracking for shimmer
  bool _isInitialLoadProd = true;
  bool _isInitialLoadShop = true;
  Timer? _shimmerSafetyTimer;
  static const Duration _maxShimmerDuration = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _startShimmerSafetyTimer();

    _tabController = TabController(length: 2, vsync: this)
      ..animation?.addListener(() => setState(() {}));
    _prodController = ScrollController()..addListener(_prodOnScroll);
    _shopController = ScrollController()..addListener(_shopOnScroll);
    _fetchProdReviews();
    _fetchShopReviews();
  }

  @override
  void dispose() {
    _shimmerSafetyTimer?.cancel();
    _tabController.dispose();
    _prodController.dispose();
    _shopController.dispose();
    super.dispose();
  }

  /// Safety timer to prevent shimmer from getting stuck
  void _startShimmerSafetyTimer() {
    _shimmerSafetyTimer = Timer(_maxShimmerDuration, () {
      if (mounted) {
        setState(() {
          _isInitialLoadProd = false;
          _isInitialLoadShop = false;
        });
      }
    });
  }

  /// End initial load for product reviews tab
  void _endInitialLoadProd() {
    if (mounted && _isInitialLoadProd) {
      setState(() => _isInitialLoadProd = false);
    }
  }

  /// End initial load for shop reviews tab
  void _endInitialLoadShop() {
    if (mounted && _isInitialLoadShop) {
      setState(() => _isInitialLoadShop = false);
    }
  }

  Widget _buildModernTabBar() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Detect tablet for centering tabs
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isLight
          ? Colors.grey.withOpacity(0.1)
          : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: isTablet ? TabAlignment.center : TabAlignment.start,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [jadeGreen, Color(0xFF00C574)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: jadeGreen.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isLight ? Colors.grey[600] : Colors.grey[400],
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
          _buildModernTab(AppLocalizations.of(context).productReviews, Icons.storefront_outlined),
          _buildModernTab(AppLocalizations.of(context).shopReviews, Icons.shop_rounded),
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

  void _prodOnScroll() {
    if (_prodController.position.pixels >=
            _prodController.position.maxScrollExtent - 100 &&
        !_prodLoading &&
        _prodHasMore) {
      _fetchProdReviews();
    }
  }

  void _shopOnScroll() {
    if (_shopController.position.pixels >=
            _shopController.position.maxScrollExtent - 100 &&
        !_shopLoading &&
        _shopHasMore) {
      _fetchShopReviews();
    }
  }

 Future<void> _fetchProdReviews() async {
  if (!_prodHasMore) return;
  setState(() => _prodLoading = true);

  try {
    // 1️⃣ Query reviews from shop_products collection for this shop
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where('shopId', isEqualTo: widget.shopId)
        .where('isProductReview', isEqualTo: true); // ✅ CHANGED: Use this instead

    // 2️⃣ Apply product filter if set
    if (_currentProductFilter != null) {
      query = query.where('productId', isEqualTo: _currentProductFilter);
    }

    // 3️⃣ Apply date range filters if set
    if (_currentStartDate != null) {
      query = query.where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!),
      );
    }
    if (_currentEndDate != null) {
      final nextDay = _currentEndDate!.add(const Duration(days: 1));
      query = query.where(
        'timestamp',
        isLessThan: Timestamp.fromDate(nextDay),
      );
    }

    // 4️⃣ Always order & page
    query = query.orderBy('timestamp', descending: true).limit(_pageSize);

    if (_prodLastDoc != null) {
      query = query.startAfterDocument(_prodLastDoc!);
    }

    // 5️⃣ Execute
    final snap = await query.get();
    final docs = snap.docs;
    if (docs.length < _pageSize) _prodHasMore = false;
    if (docs.isNotEmpty) _prodLastDoc = docs.last;

    // 6️⃣ Update state
    if (mounted) {
      setState(() {
        _prodDocs.addAll(docs);
        _prodLoading = false;
      });
    }
    _endInitialLoadProd();
  } catch (e) {
    debugPrint('Error fetching product reviews: $e');
    _endInitialLoadProd();
    if (mounted) {
      setState(() => _prodLoading = false);
    }
  }
}

  Future<void> _fetchShopReviews() async {
    if (!_shopHasMore) return;
    setState(() => _shopLoading = true);
    
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('reviews')
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);
      if (_shopLastDoc != null) query = query.startAfterDocument(_shopLastDoc!);

      final snap = await query.get();
      final docs = snap.docs;
      if (docs.length < _pageSize) _shopHasMore = false;
      if (docs.isNotEmpty) _shopLastDoc = docs.last;

      if (mounted) {
        setState(() {
          _shopDocs.addAll(docs);
          _shopLoading = false;
        });
      }
      _endInitialLoadShop();
    } catch (e) {
      debugPrint('Error fetching shop reviews: $e');
      _endInitialLoadShop();
      if (mounted) {
        setState(() => _shopLoading = false);
      }
    }
  }

  Future<void> _pickDateRange() async {
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
        // reset product-reviews pagination:
        _prodDocs.clear();
        _prodLastDoc = null;
        _prodHasMore = true;
        // reset shop-reviews pagination if you want date filtering there:
        _shopDocs.clear();
        _shopLastDoc = null;
        _shopHasMore = true;
      });
      await _fetchProdReviews();
      await _fetchShopReviews();
    }
  }

  int _getActiveFiltersCount() {
    int count = 0;
    if (_currentProductFilter != null) count++;
    if (_currentStartDate != null || _currentEndDate != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.reviews,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              Icons.date_range_rounded,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            onPressed: _pickDateRange,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _buildModernTabBar(),
        ),
      ),
      body: Container(
        color: isDarkMode
            ? const Color(0xFF1C1A29)
            : const Color.fromARGB(255, 240, 240, 240),
        child: SafeArea(
          bottom: true,
          child: Column(
            children: [
              // Filter button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: _getActiveFiltersCount() > 0
                        ? Colors.orange
                        : Colors.transparent,
                    side: BorderSide(
                      color: _getActiveFiltersCount() > 0
                          ? Colors.orange
                          : Colors.grey.shade300,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: Icon(
                    Icons.filter_list,
                    color: _getActiveFiltersCount() > 0
                        ? Colors.white
                        : (isDarkMode ? Colors.white : Colors.black),
                  ),
                  label: Text(
                    _getActiveFiltersCount() > 0
                        ? '${l10n.filter} (${_getActiveFiltersCount()})'
                        : l10n.filter,
                    style: TextStyle(
                      color: _getActiveFiltersCount() > 0
                          ? Colors.white
                          : (isDarkMode ? Colors.white : Colors.black),
                    ),
                  ),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DynamicReviewsFilterScreen(
                          sellerId: widget.shopId,
                          isShopProduct: true,
                          initialProductId: _currentProductFilter,
                        ),
                      ),
                    );
                    if (result != null) {
                      setState(() {
                        _currentProductFilter = result['productId'];
                        // reset product-reviews pagination:
                        _prodDocs.clear();
                        _prodLastDoc = null;
                        _prodHasMore = true;
                        // reset shop-reviews pagination:
                        _shopDocs.clear();
                        _shopLastDoc = null;
                        _shopHasMore = true;
                      });
                      await _fetchProdReviews();
                      await _fetchShopReviews();
                    }
                  },
                ),
              ),

              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildList(
                      _prodDocs,
                      _prodLoading,
                      _prodController,
                      isProduct: true,
                      isInitialLoad: _isInitialLoadProd,
                    ),
                    _buildList(
                      _shopDocs,
                      _shopLoading,
                      _shopController,
                      isProduct: false,
                      isInitialLoad: _isInitialLoadShop,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds shimmer placeholder for reviews list
  Widget _buildReviewsShimmer(bool isDarkMode) {
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
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
                  // Product card shimmer
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 14,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 12,
                              width: 100,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Review content shimmer
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reviewer name
                        Container(
                          height: 12,
                          width: 120,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Stars
                        Row(
                          children: List.generate(5, (index) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          )),
                        ),
                        const SizedBox(height: 8),
                        // Review text
                        Container(
                          height: 14,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 14,
                          width: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  bool loading,
  ScrollController controller, {
  required bool isProduct,
  required bool isInitialLoad,
}) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  // Show shimmer during initial load
  if (isInitialLoad) {
    return _buildReviewsShimmer(isDarkMode);
  }

  if (docs.isEmpty && !loading) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/reviews.png', width: 140),
          const SizedBox(height: 12),
          Text(
            l10n.noReceivedReviews,
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
    controller: controller,
    padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
    itemCount: docs.length + (loading ? 1 : 0),
    separatorBuilder: (_, __) => const SizedBox(height: 16),
    itemBuilder: (context, index) {
      if (index >= docs.length) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = docs[index].data();
      final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
      final reviewText = data['review'] as String? ?? '';

      if (isProduct) {
        // Enhanced product review display
        final productName = data['productName'] as String? ?? 'Unknown Product';
        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
        final currency = data['currency'] as String? ?? 'TL';
        
        // Enhanced image selection - prioritize selected color image
        final productImage = data['productImage'] as String? ?? '';
        final selectedColorImage = data['selectedColorImage'] as String?;
        final imageUrl = selectedColorImage ?? productImage;
        
        // Brand information
        final brand = data['brand'] as String? ?? '';
        final brandModel = data['brandModel'] as String? ?? brand;
        
        // Build color images map for ProductCard4
        final colorImages = <String, List<String>>{};
        final selectedColor = data['selectedColor'] as String?;
        if (selectedColor != null && selectedColorImage != null) {
          colorImages[selectedColor] = [selectedColorImage];
        }
        
        // Review images
        final imageUrls = (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? <String>[];

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 40, 37, 56)
                : Colors.white,
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
                // Product info section with enhanced data
                GestureDetector(
                  onTap: () {
                    context.push('/product/${data['productId']}');
                  },
                  child: ProductCard4(
                    imageUrl: imageUrl,
                    colorImages: colorImages,
                    productName: productName,
                    brandModel: brandModel,
                    price: price,
                    currency: currency,
                    averageRating: rating, // Show the rating given in this review
                    showOverlayIcons: false,
                    isShopProduct: true,
                  ),
                ),
                
                // Additional product context (optional)
                if (selectedColor != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Color: $selectedColor',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
                
                const SizedBox(height: 8),
                
                // Review content section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF1C1A29)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reviewer info
                      Text(
                        'Review by: ${data['userName'] ?? 'Anonymous'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      
                      // Rating stars
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          5,
                          (idx) => Icon(
                            idx < rating ? Icons.star : Icons.star_border,
                            size: 16,
                            color: const Color(0xFFFFD700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Review text
                      Text(
                        reviewText,
                        style: const TextStyle(fontSize: 14),
                      ),
                      
                      // Review images
                      if (imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: imageUrls.take(3).map((url) => Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      backgroundColor: Colors.black,
                                      appBar: AppBar(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        leading: const BackButton(color: Colors.white),
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
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    url,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.image, color: Colors.grey),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            )).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Seller review display (keep your existing logic)
        final sellerName = data['sellerName'] as String? ?? '';
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 40, 37, 56)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16.0),
            title: Text(sellerName),
            subtitle: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1C1A29) : Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (idx) => Icon(
                        idx < rating ? Icons.star : Icons.star_border,
                        size: 16,
                        color: const Color.fromARGB(255, 242, 194, 0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    reviewText,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    },
  );
}
}