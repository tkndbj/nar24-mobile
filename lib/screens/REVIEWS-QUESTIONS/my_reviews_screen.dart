import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/product_card_4.dart';
import '../../providers/review_provider.dart';
import 'review_dialog.dart';
import '../../models/review_dialog_view_model.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/image_compression_utils.dart';

const int _kMaxImages = 3;
const int _kMaxFileSizeBytes = 5 * 1024 * 1024; // 5MB
const List<String> _kValidExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.heic',
  '.heif',
  '.webp',
];

// ─────────────────────────────────────────────────────────────────────────────
// Local models
// ─────────────────────────────────────────────────────────────────────────────

class FoodPendingReview {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String? restaurantProfileImage;
  final List<Map<String, dynamic>> items;
  final double totalPrice;
  final String currency;
  final Timestamp createdAt;

  const FoodPendingReview({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    this.restaurantProfileImage,
    required this.items,
    required this.totalPrice,
    required this.currency,
    required this.createdAt,
  });

  factory FoodPendingReview.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final rawItems = d['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map((i) =>
                {'name': i['name'] ?? '', 'quantity': i['quantity'] ?? 1})
            .toList()
        : <Map<String, dynamic>>[];
    return FoodPendingReview(
      id: doc.id,
      restaurantId: d['restaurantId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String? ?? '',
      restaurantProfileImage: d['restaurantProfileImage'] as String?,
      items: items,
      totalPrice: (d['totalPrice'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'TL',
      createdAt: d['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  String get itemsPreview {
    final preview = items.take(2).map((i) {
      final qty = (i['quantity'] as num?)?.toInt() ?? 1;
      final name = i['name'] as String? ?? '';
      return qty > 1 ? '${qty}× $name' : name;
    }).join(', ');
    return items.length > 2 ? '$preview +${items.length - 2}' : preview;
  }
}

class FoodReview {
  final String id;
  final String orderId;
  final String buyerId;
  final String? restaurantName;
  final String restaurantId;
  final double rating;
  final String comment;
  final Timestamp timestamp;
  final List<String> imageUrls;

  const FoodReview({
    required this.id,
    required this.orderId,
    required this.buyerId,
    this.restaurantName,
    required this.restaurantId,
    required this.rating,
    required this.comment,
    required this.timestamp,
    required this.imageUrls,
  });

  factory FoodReview.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return FoodReview(
      id: doc.id,
      orderId: d['orderId'] as String? ?? '',
      buyerId: d['buyerId'] as String? ?? '',
      restaurantName: d['restaurantName'] as String?,
      restaurantId: d['restaurantId'] as String? ?? '',
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      comment: d['comment'] as String? ?? '',
      timestamp: d['timestamp'] as Timestamp? ?? Timestamp.now(),
      imageUrls: (d['imageUrls'] as List<dynamic>?) // ← ADD THIS
              ?.whereType<String>()
              .toList() ??
          [],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter enum (added food)
// ─────────────────────────────────────────────────────────────────────────────

enum ReviewFilter { all, product, seller, food }

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({Key? key}) : super(key: key);

  @override
  _MyReviewsScreenState createState() => _MyReviewsScreenState();
}

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

  // ── My product/seller reviews ──────────────────────────────────────────────
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _myDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _myLastDoc;
  bool _myHasMore = true;
  bool _myLoading = false;
  bool _myInitialLoading = true;

  // ── Pending food reviews ───────────────────────────────────────────────────
  final List<FoodPendingReview> _foodPending = [];
  DocumentSnapshot? _foodPendingLastDoc;
  bool _foodPendingHasMore = true;
  bool _foodPendingLoading = false;
  bool _foodPendingInitialLoading = true;

  // ── My food reviews ────────────────────────────────────────────────────────
  final List<FoodReview> _myFoodReviews = [];
  DocumentSnapshot? _myFoodLastDoc;
  bool _myFoodHasMore = true;
  bool _myFoodLoading = false;
  bool _myFoodInitialLoading = true;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _pendingController = ScrollController()..addListener(_pendingOnScroll);
    _myController = ScrollController()..addListener(_myOnScroll);

    _fetchMyReviewPage();
    _fetchFoodPendingPage();
    _fetchMyFoodReviewsPage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pendingController.dispose();
    _myController.dispose();
    super.dispose();
  }

  // ── Scroll listeners ────────────────────────────────────────────────────────

  void _pendingOnScroll() {
    final provider = context.read<ReviewProvider>();
    if (_pendingController.position.pixels >=
            _pendingController.position.maxScrollExtent - 200 &&
        provider.canLoadMore) {
      provider.loadMore();
    }
    if (_pendingController.position.pixels >=
            _pendingController.position.maxScrollExtent - 200 &&
        !_foodPendingLoading &&
        _foodPendingHasMore) {
      _fetchFoodPendingPage();
    }
  }

  void _myOnScroll() {
    if (_myController.position.pixels >=
        _myController.position.maxScrollExtent - 200) {
      if (!_myLoading && _myHasMore) _fetchMyReviewPage();
      if (!_myFoodLoading &&
          _myFoodHasMore &&
          (_filter == ReviewFilter.all || _filter == ReviewFilter.food)) {
        _fetchMyFoodReviewsPage();
      }
    }
  }

  // ── Fetch product/seller reviews ────────────────────────────────────────────

  Future<void> _fetchMyReviewPage({bool reset = false}) async {
    if (!_myHasMore || _myLoading) return;
    setState(() => _myLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _myLoading = false);
        return;
      }

      late Query<Map<String, dynamic>> q;
      switch (_filter) {
        case ReviewFilter.product:
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid)
              .where('productId', isNotEqualTo: null);
          break;
        case ReviewFilter.seller:
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid)
              .where('productId', isEqualTo: null);
          break;
        case ReviewFilter.food:
          // No product reviews to show in food-only filter
          if (mounted) {
            setState(() {
              _myLoading = false;
              _myInitialLoading = false;
              _myHasMore = false;
            });
          }
          return;
        default:
          q = FirebaseFirestore.instance
              .collectionGroup('reviews')
              .where('userId', isEqualTo: uid);
      }

      if (_currentSellerFilter != null) {
        q = q.where('sellerId', isEqualTo: _currentSellerFilter);
      }
      if (_currentProductFilter != null) {
        q = q.where('productId', isEqualTo: _currentProductFilter);
      }
      if (_currentStartDate != null) {
        q = q.where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!));
      }
      if (_currentEndDate != null) {
        final end = DateTime(_currentEndDate!.year, _currentEndDate!.month,
            _currentEndDate!.day, 23, 59, 59);
        q = q.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      q = q.orderBy('timestamp', descending: true).limit(_pageSize);
      if (_myLastDoc != null) q = q.startAfterDocument(_myLastDoc!);

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

  // ── Fetch food pending reviews ──────────────────────────────────────────────

  Future<void> _fetchFoodPendingPage({bool reset = false}) async {
    if (!_foodPendingHasMore || _foodPendingLoading) return;
    setState(() => _foodPendingLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _foodPendingLoading = false);
        return;
      }

      Query q = FirebaseFirestore.instance
          .collection('orders-food')
          .where('buyerId', isEqualTo: uid)
          .where('needsReview', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (_foodPendingLastDoc != null) {
        q = q.startAfterDocument(_foodPendingLastDoc!);
      }

      final snap = await q.get();

      if (snap.docs.length < _pageSize) _foodPendingHasMore = false;
      if (snap.docs.isNotEmpty) _foodPendingLastDoc = snap.docs.last;

      final newItems =
          snap.docs.map((d) => FoodPendingReview.fromDoc(d)).toList();

      if (mounted) {
        setState(() {
          _foodPending.addAll(newItems);
          _foodPendingLoading = false;
          _foodPendingInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching food pending reviews: $e');
      if (mounted) {
        setState(() {
          _foodPendingLoading = false;
          _foodPendingInitialLoading = false;
        });
      }
    }
  }

  // ── Fetch my food reviews ───────────────────────────────────────────────────

  Future<void> _fetchMyFoodReviewsPage({bool reset = false}) async {
    if (!_myFoodHasMore || _myFoodLoading) return;
    setState(() => _myFoodLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _myFoodLoading = false);
        return;
      }

      Query q = FirebaseFirestore.instance
          .collectionGroup('food-reviews')
          .where('buyerId', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (_myFoodLastDoc != null) {
        q = q.startAfterDocument(_myFoodLastDoc!);
      }

      final snap = await q.get();

      if (snap.docs.length < _pageSize) _myFoodHasMore = false;
      if (snap.docs.isNotEmpty) _myFoodLastDoc = snap.docs.last;

      final newItems = snap.docs.map((d) => FoodReview.fromDoc(d)).toList();

      if (mounted) {
        setState(() {
          _myFoodReviews.addAll(newItems);
          _myFoodLoading = false;
          _myFoodInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching food reviews: $e');
      if (mounted) {
        setState(() {
          _myFoodLoading = false;
          _myFoodInitialLoading = false;
        });
      }
    }
  }

  // ── Reset helpers ───────────────────────────────────────────────────────────

  void _resetProductReviews() {
    _myDocs.clear();
    _myLastDoc = null;
    _myHasMore = true;
    _myInitialLoading = true;
  }

  void _resetFoodReviews() {
    _myFoodReviews.clear();
    _myFoodLastDoc = null;
    _myFoodHasMore = true;
    _myFoodInitialLoading = true;
  }

  // ── Date picker ─────────────────────────────────────────────────────────────

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
              end: DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
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
          ),
          dialogTheme: DialogThemeData(backgroundColor: backgroundColor),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _currentStartDate = picked.start;
        _currentEndDate = picked.end;
        _resetProductReviews();
        _resetFoodReviews();
      });
      await _fetchMyReviewPage();
      await _fetchMyFoodReviewsPage();
    }
  }

  // ── Loading modal ───────────────────────────────────────────────────────────

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
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
                      child: const Icon(Icons.rate_review,
                          color: Colors.white, size: 32),
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
                l10n.pleaseWaitWhileWeProcessYourReview ??
                    'Please wait while we process your review.',
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
                            Color(0xFF00A86B)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Food review bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showFoodReviewBottomSheet(FoodPendingReview order) async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double localRating = 0;
    final textController = TextEditingController();
    final List<File> selectedImages = [];

    String? _validateFile(File file) {
      final size = file.lengthSync();
      if (size > _kMaxFileSizeBytes) return 'Image must be under 5 MB.';
      final name = file.path.toLowerCase();
      final valid = _kValidExtensions.any((ext) => name.endsWith(ext));
      if (!valid) return 'Only JPG, PNG, HEIC, or WEBP images are allowed.';
      return null;
    }

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> pickImage() async {
            if (selectedImages.length >= _kMaxImages) return;
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
            if (picked == null) return;
            final file = File(picked.path);
            final error = _validateFile(file);
            if (error != null) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(error), backgroundColor: Colors.red),
                );
              }
              return;
            }
            setModalState(() => selectedImages.add(file));
          }

          return GestureDetector(
            onTap: () => FocusScope.of(ctx).unfocus(),
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Material(
                color: Colors.transparent,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color.fromARGB(255, 33, 31, 49)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFF97316).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.restaurant_menu_rounded,
                                    color: Color(0xFFF97316), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.restaurantReview,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    Text(
                                      order.restaurantName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Items preview
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.05)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    order.itemsPreview,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Stars
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    5,
                                    (idx) => GestureDetector(
                                      onTap: () => setModalState(() =>
                                          localRating = (idx + 1).toDouble()),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          idx < localRating
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          color: Colors.amber,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Text input
                                Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromARGB(255, 45, 43, 61)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: isDark
                                            ? Colors.grey.shade600
                                            : Colors.grey.shade300),
                                  ),
                                  child: CupertinoTextField(
                                    controller: textController,
                                    placeholder: l10n.pleaseEnterYourReview ??
                                        'Write your review...',
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 14,
                                    ),
                                    cursorColor:
                                        isDark ? Colors.white : Colors.black,
                                    maxLines: 4,
                                    decoration:
                                        const BoxDecoration(border: Border()),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Image section
                                Text(
                                  'Photos (optional, up to $_kMaxImages)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // Selected image thumbnails
                                    ...selectedImages.map(
                                      (file) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.file(
                                                file,
                                                width: 64,
                                                height: 64,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            Positioned(
                                              top: 2,
                                              right: 2,
                                              child: GestureDetector(
                                                onTap: () => setModalState(() =>
                                                    selectedImages
                                                        .remove(file)),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(3),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.close,
                                                      color: Colors.white,
                                                      size: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Add button
                                    if (selectedImages.length < _kMaxImages)
                                      GestureDetector(
                                        onTap: pickImage,
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.grey.shade600
                                                  : Colors.grey.shade300,
                                              width: 1.5,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            color: isDark
                                                ? Colors.white.withOpacity(0.05)
                                                : Colors.grey.shade50,
                                          ),
                                          child: Icon(
                                            Icons.add_photo_alternate_rounded,
                                            size: 28,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[500],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Buttons
                        SafeArea(
                          top: false,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: CupertinoButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(
                                      l10n.cancel,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: CupertinoButton(
                                    color: const Color(0xFFF97316),
                                    onPressed: localRating == 0 ||
                                            textController.text.trim().isEmpty
                                        ? null
                                        : () {
                                            Navigator.pop(ctx);
                                            _submitFoodReview(
                                              order: order,
                                              rating: localRating,
                                              comment:
                                                  textController.text.trim(),
                                              images: List.from(selectedImages),
                                            );
                                          },
                                    child: Text(
                                      l10n.submit,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Submit food review ──────────────────────────────────────────────────────

  Future<void> _submitFoodReview({
    required FoodPendingReview order,
    required double rating,
    required String comment,
    List<File> images = const [],
  }) async {
    final l10n = AppLocalizations.of(context);
    _showLoadingModal(l10n);

    try {
      // Upload and moderate images
      final approvedUrls = <String>[];
      final storage = FirebaseStorage.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      for (int i = 0; i < images.length; i++) {
        // Compress
        final compressed =
            await ImageCompressionUtils.ecommerceCompress(images[i]);
        final fileToUpload = compressed ?? images[i];

        // Upload
        final path =
            'restaurant_reviews/${order.restaurantId}/${uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final ref = storage.ref().child(path);
        await ref.putFile(fileToUpload);
        final url = await ref.getDownloadURL();

        // Moderate
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
            .httpsCallable('moderateImage');
        final result = await callable.call({'imageUrl': url});
        final data = result.data as Map<String, dynamic>;

        if (data['approved'] == true) {
          approvedUrls.add(url);
        } else {
          // Delete rejected image from storage
          await ref.delete();
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(l10n.imageRejectedWithNumber('${i + 1}')),
            backgroundColor: Colors.red,
          ));
          return;
        }
      }

      // Submit review
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('submitRestaurantReview');

      await callable.call({
        'orderId': order.id,
        'restaurantId': order.restaurantId,
        'rating': rating,
        'comment': comment,
        'imageUrls': approvedUrls,
      });

      if (!mounted) return;
      Navigator.of(context).pop();

      setState(() {
        _foodPending.removeWhere((o) => o.id == order.id);
      });

      _showSuccessSnackbar(l10n);

      setState(() {
        _myFoodReviews.clear();
        _myFoodLastDoc = null;
        _myFoodHasMore = true;
        _myFoodInitialLoading = true;
      });
      await _fetchMyFoodReviewsPage();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message ?? l10n.errorSubmittingReview),
        backgroundColor: Colors.red,
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.errorSubmittingReview),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReviewShimmerItem(bool isDark) {
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

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
                        borderRadius: BorderRadius.circular(8)),
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
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 100,
                          decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(4)),
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
                    color: baseColor, borderRadius: BorderRadius.circular(8)),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Tab bar
  // ─────────────────────────────────────────────────────────────────────────

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
        labelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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

  // ── Filter row (now with Food chip) ────────────────────────────────────────

  Widget _buildFilterRow(bool isDark, AppLocalizations l10n) {
    const buttonWidth = 110.0;
    final borderColor = isDark ? Colors.grey.shade600 : Colors.grey.shade500;

    Widget chip(String label, ReviewFilter value, Color activeColor) {
      final isActive = _filter == value;
      return SizedBox(
        width: buttonWidth,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: isActive ? activeColor : Colors.transparent,
            side: BorderSide(
              color: isActive ? activeColor : borderColor,
              width: 1.2,
            ),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(vertical: 10),
            minimumSize: const Size(buttonWidth, 0),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black),
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          onPressed: () {
            setState(() {
              _filter = (_filter == value) ? ReviewFilter.all : value;
              _resetProductReviews();
              _resetFoodReviews();
              if (_filter != ReviewFilter.food) {
                _myHasMore = true;
              }
              if (_filter == ReviewFilter.all || _filter == ReviewFilter.food) {
                _myFoodHasMore = true;
              }
            });
            if (_filter != ReviewFilter.food) _fetchMyReviewPage();
            if (_filter == ReviewFilter.all || _filter == ReviewFilter.food) {
              _fetchMyFoodReviewsPage();
            }
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          chip(l10n.product, ReviewFilter.product, Colors.orange),
          const SizedBox(width: 8),
          chip(l10n.seller, ReviewFilter.seller, Colors.orange),
          const SizedBox(width: 8),
          chip(
            l10n.food,
            ReviewFilter.food,
            const Color(0xFFF97316),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

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
        iconTheme:
            IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        title: Text(
          l10n.myReviews,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.date_range_rounded,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
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

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: Pending reviews
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPendingList(List pending, bool isDark, AppLocalizations l10n) {
    final totalPending = pending.length + _foodPending.length;

    if (totalPending == 0 && !_foodPendingLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/reviews.png', width: 140),
            const SizedBox(height: 12),
            Text(
              l10n.nothingToReview,
              style: TextStyle(
                  fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _pendingController,
      padding: const EdgeInsets.only(top: 8.0),
      itemCount:
          pending.length + _foodPending.length + (_foodPendingLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        // Product/seller pending items first
        if (index < pending.length) {
          final pr = pending[index];
          final data = pr.txDoc.data() as Map<String, dynamic>;
          final imageUrl = data['productImage'] as String? ?? '';
          final colorImages = <String, List<String>>{};
          final selectedColor = data['selectedColor'] as String?;
          if (selectedColor != null && imageUrl.isNotEmpty) {
            colorImages[selectedColor] = [imageUrl];
          }
          return _buildProductPendingCard(
              pr, data, imageUrl, colorImages, isDark, l10n);
        }

        // Food pending items
        final foodIndex = index - pending.length;
        if (foodIndex < _foodPending.length) {
          return _buildFoodPendingCard(_foodPending[foodIndex], isDark, l10n);
        }

        // Loading shimmer
        return _buildReviewShimmerItem(isDark);
      },
    );
  }

  Widget _buildProductPendingCard(
    dynamic pr,
    Map<String, dynamic> data,
    String imageUrl,
    Map<String, List<String>> colorImages,
    bool isDark,
    AppLocalizations l10n,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => context.push('/product/${pr.productId}'),
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
                      label: Text(l10n.writeYourReview,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
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
                        pr.isShopProduct ? l10n.shopReview : l10n.sellerReview3,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF28C38),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
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
  }

  Widget _buildFoodPendingCard(
      FoodPendingReview order, bool isDark, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Restaurant avatar / icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFF97316).withOpacity(0.1),
                  ),
                  child: order.restaurantProfileImage != null &&
                          order.restaurantProfileImage!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            order.restaurantProfileImage!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.restaurant_menu_rounded,
                          color: Color(0xFFF97316), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order.itemsPreview,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${order.totalPrice.toStringAsFixed(0)} ${order.currency}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF97316),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${order.createdAt.toDate().day}/'
                  '${order.createdAt.toDate().month}/'
                  '${order.createdAt.toDate().year}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton.icon(
              onPressed: () => _showFoodReviewBottomSheet(order),
              icon: const Icon(Icons.star_rounded, size: 18),
              label: Text(
                l10n.writeRestaurantReview,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: My reviews
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMyReviewsList(bool isDark, AppLocalizations l10n) {
    final Widget content;

    if (_myInitialLoading && _myFoodInitialLoading) {
      content = _buildShimmerList(isDark);
    } else {
      final showFood =
          _filter == ReviewFilter.all || _filter == ReviewFilter.food;
      final showProduct = _filter != ReviewFilter.food;

      final displayedDocs = showProduct
          ? _myDocs.where((doc) {
              final collId = doc.reference.parent.parent?.parent.id;
              switch (_filter) {
                case ReviewFilter.product:
                  return collId == 'products' || collId == 'shop_products';
                case ReviewFilter.seller:
                  return collId == 'users' || collId == 'shops';
                default:
                  return true;
              }
            }).toList()
          : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      final foodReviews = showFood ? _myFoodReviews : <FoodReview>[];
      final totalCount = displayedDocs.length + foodReviews.length;

      if (totalCount == 0 && !_myLoading && !_myFoodLoading) {
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/reviews.png', width: 140),
              const SizedBox(height: 12),
              Text(
                l10n.youHaveNoReviews,
                style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        );
      } else {
        content = ListView.separated(
          controller: _myController,
          padding: const EdgeInsets.only(top: 8.0),
          itemCount: displayedDocs.length +
              foodReviews.length +
              (_myLoading || _myFoodLoading ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            // Product / seller reviews
            if (index < displayedDocs.length) {
              return _buildProductReviewCard(
                  displayedDocs[index], isDark, l10n);
            }

            // Food reviews
            final foodIndex = index - displayedDocs.length;
            if (foodIndex < foodReviews.length) {
              return _buildFoodReviewCard(foodReviews[foodIndex], isDark, l10n);
            }

            // Loading shimmer
            return _buildReviewShimmerItem(isDark);
          },
        );
      }
    }

    return Column(
      children: [
        _buildFilterRow(isDark, l10n),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildProductReviewCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final data = doc.data();
    final collectionId = doc.reference.parent.parent?.parent.id;
    final parentDocRef = doc.reference.parent.parent!;
    final parentCollection = parentDocRef.parent.id;
    final parentId = parentDocRef.id;
    final imageUrl = data['productImage'] as String? ?? '';
    final productName = data['productName'] as String? ?? '';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final currency = data['currency'] as String? ?? '';
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final reviewText = data['review'] as String? ?? '';
    final imageUrls =
        (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1)),
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
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 16),
                      ),
                      TextSpan(
                        text: data['sellerName'] as String? ?? l10n.unknownSeller,
                        style: TextStyle(
                            fontWeight: FontWeight.normal,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              GestureDetector(
                onTap: () => context.push('/product/${data['productId']}'),
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
                color:
                    isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
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
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(context)
                                        .push(MaterialPageRoute(
                                      builder: (_) => Scaffold(
                                        backgroundColor: Colors.black,
                                        appBar: AppBar(
                                          backgroundColor: Colors.transparent,
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
                                    )),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(url,
                                          height: 60,
                                          width: 60,
                                          fit: BoxFit.cover),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(reviewText, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodReviewCard(
      FoodReview review, bool isDark, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 2,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.restaurant_menu_rounded,
                      color: Color(0xFFF97316), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.restaurantName ??
                            l10n.restaurantReview,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: List.generate(
                          5,
                          (idx) => Icon(
                            idx < review.rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: Colors.amber,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${review.timestamp.toDate().day}/'
                  '${review.timestamp.toDate().month}/'
                  '${review.timestamp.toDate().year}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                ),
              ],
            ),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1A29)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    Text(review.comment, style: const TextStyle(fontSize: 14)),
              ),
            ],
            if (review.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            leading: const BackButton(color: Colors.white),
                          ),
                          body: Center(
                            child: InteractiveViewer(
                              child: Image.network(review.imageUrls[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        review.imageUrls[i],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Product review dialog (unchanged logic)
  // ─────────────────────────────────────────────────────────────────────────

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

      final viewModel = ReviewDialogViewModel(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
        storage: storage,
        orderId: orderId,
      );

      await showCupertinoModalPopup<bool>(
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
            if (mounted) {
              _showLoadingModal(l10n);
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
                    Navigator.of(context).pop();
                    _showSuccessSnackbar(l10n);
                    context.read<ReviewProvider>().loadPendingReviews(
                        FirebaseAuth.instance.currentUser!.uid);
                    setState(() {
                      _resetProductReviews();
                    });
                    _fetchMyReviewPage();
                  }
                },
                onError: (error) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(l10n.errorSubmittingReview),
                      backgroundColor: Colors.red,
                    ));
                  }
                },
              );
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('Error showing review dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.errorSubmittingReview),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}
