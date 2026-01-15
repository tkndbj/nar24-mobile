import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/product_card_4.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// A screen for shop members to view, answer, or delete product questions.
class SellerPanelProductQuestions extends StatefulWidget {
  final String shopId;
  const SellerPanelProductQuestions({Key? key, required this.shopId})
      : super(key: key);

  @override
  _SellerPanelProductQuestionsState createState() =>
      _SellerPanelProductQuestionsState();
}

class _SellerPanelProductQuestionsState
    extends State<SellerPanelProductQuestions>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;

  late TabController _tabController;
  late ScrollController _unansweredController;
  late ScrollController _answeredController;

  String? _currentProductFilter;
  DateTime? _currentStartDate;
  DateTime? _currentEndDate;

  static const Color jadeGreen = Color(0xFF00A86B);

  // pagination state
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _unansweredDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _unansweredLastDoc;
  bool _unansweredHasMore = true;
  bool _unansweredLoading = false;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _answeredDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _answeredLastDoc;
  bool _answeredHasMore = true;
  bool _answeredLoading = false;

  // Initial load tracking for shimmer
  bool _isInitialLoadUnanswered = true;
  bool _isInitialLoadAnswered = true;
  Timer? _shimmerSafetyTimer;
  static const Duration _maxShimmerDuration = Duration(seconds: 12);

  // Viewer role state
  bool _isViewer = false;

  @override
  void initState() {
    super.initState();
    _startShimmerSafetyTimer();
    _checkUserRole();

    _tabController = TabController(length: 2, vsync: this)
      ..animation?.addListener(() => setState(() {}));

    _unansweredController = ScrollController()
      ..addListener(_unansweredOnScroll);
    _answeredController = ScrollController()..addListener(_answeredOnScroll);

    _fetchUnansweredPage();
    _fetchAnsweredPage();
  }

  /// Checks if the current user has only viewer role for the shop.
  Future<void> _checkUserRole() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();

      if (shopDoc.exists && mounted) {
        final shopData = shopDoc.data();
        if (shopData != null) {
          final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
          setState(() {
            _isViewer = viewers.contains(currentUserId);
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking user role: $e');
    }
  }

  @override
  void dispose() {
    _shimmerSafetyTimer?.cancel();
    _tabController.dispose();
    _unansweredController.dispose();
    _answeredController.dispose();
    super.dispose();
  }

  /// Safety timer to prevent shimmer from getting stuck
  void _startShimmerSafetyTimer() {
    _shimmerSafetyTimer = Timer(_maxShimmerDuration, () {
      if (mounted) {
        setState(() {
          _isInitialLoadUnanswered = false;
          _isInitialLoadAnswered = false;
        });
      }
    });
  }

  /// End initial load for unanswered tab
  void _endInitialLoadUnanswered() {
    if (mounted && _isInitialLoadUnanswered) {
      setState(() => _isInitialLoadUnanswered = false);
    }
  }

  /// End initial load for answered tab
  void _endInitialLoadAnswered() {
    if (mounted && _isInitialLoadAnswered) {
      setState(() => _isInitialLoadAnswered = false);
    }
  }

  Widget _buildModernTabBar() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final l10n = AppLocalizations.of(context);

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
        tabAlignment: TabAlignment.center,
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
          _buildModernTab(
              l10n.unanswered ?? 'Unanswered', Icons.help_outline_rounded),
          _buildModernTab(l10n.answered ?? 'Answered', Icons.inbox_rounded),
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

  void _unansweredOnScroll() {
    if (_unansweredController.position.pixels >=
            _unansweredController.position.maxScrollExtent - 100 &&
        !_unansweredLoading &&
        _unansweredHasMore) {
      _fetchUnansweredPage();
    }
  }

  void _answeredOnScroll() {
    if (_answeredController.position.pixels >=
            _answeredController.position.maxScrollExtent - 100 &&
        !_answeredLoading &&
        _answeredHasMore) {
      _fetchAnsweredPage();
    }
  }

  Future<void> _fetchUnansweredPage() async {
    if (!_unansweredHasMore) return;
    setState(() => _unansweredLoading = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collectionGroup('product_questions')
          .where('sellerId', isEqualTo: widget.shopId)
          .where('answered', isEqualTo: false);

      if (_currentProductFilter != null) {
        q = q.where('productId', isEqualTo: _currentProductFilter);
      }
      if (_currentStartDate != null) {
        q = q.where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!));
      }
      if (_currentEndDate != null) {
        final endOfDay = DateTime(_currentEndDate!.year, _currentEndDate!.month,
            _currentEndDate!.day, 23, 59, 59);
        q = q.where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
      }

      q = q.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_unansweredLastDoc != null) {
        q = q.startAfterDocument(_unansweredLastDoc!);
      }

      final snap = await q.get();
      final newDocs = snap.docs;
      if (newDocs.length < _pageSize) _unansweredHasMore = false;
      if (newDocs.isNotEmpty) _unansweredLastDoc = newDocs.last;

      if (mounted) {
        setState(() {
          _unansweredDocs.addAll(newDocs);
          _unansweredLoading = false;
        });
      }
      _endInitialLoadUnanswered();
    } catch (e) {
      debugPrint('Error fetching unanswered questions: $e');
      _endInitialLoadUnanswered();
      if (mounted) {
        setState(() => _unansweredLoading = false);
      }
    }
  }

  Future<void> _fetchAnsweredPage() async {
    if (!_answeredHasMore) return;
    setState(() => _answeredLoading = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collectionGroup('product_questions')
          .where('sellerId', isEqualTo: widget.shopId)
          .where('answered', isEqualTo: true);

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

      q = q.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_answeredLastDoc != null) {
        q = q.startAfterDocument(_answeredLastDoc!);
      }

      final snap = await q.get();
      final newDocs = snap.docs;
      if (newDocs.length < _pageSize) _answeredHasMore = false;
      if (newDocs.isNotEmpty) _answeredLastDoc = newDocs.last;

      if (mounted) {
        setState(() {
          _answeredDocs.addAll(newDocs);
          _answeredLoading = false;
        });
      }
      _endInitialLoadAnswered();
    } catch (e) {
      debugPrint('Error fetching answered questions: $e');
      _endInitialLoadAnswered();
      if (mounted) {
        setState(() => _answeredLoading = false);
      }
    }
  }

  // Enhanced answer dialog with better UI
  Future<void> _showAnswerDialog(BuildContext context, DocumentReference doc,
      {String? existingAnswer}) async {
    final controller = TextEditingController(text: existingAnswer);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    // Track submission state outside the builder to persist across rebuilds
    bool isSubmitting = false;

    await showCupertinoModalPopup(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Add listener to update character counter
          controller.addListener(() {
            setDialogState(() {});
          });

          // Detect tablet for compact modal
          final screenWidth = MediaQuery.of(ctx).size.width;
          final screenHeight = MediaQuery.of(ctx).size.height;
          final isTablet = screenWidth >= 600;

          // Compact modal for both mobile and tablet
          final double maxModalWidth = isTablet ? 500.0 : double.infinity;

          return GestureDetector(
            onTap: () => FocusScope.of(ctx).unfocus(),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    maxWidth: maxModalWidth,
                    maxHeight: screenHeight * 0.65 -
                        MediaQuery.of(ctx).viewInsets.bottom,
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
                      // Title
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
                            Icon(
                              existingAnswer != null
                                  ? Icons.edit_rounded
                                  : Icons.reply_rounded,
                              color: const Color(0xFF00A86B),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              existingAnswer != null
                                  ? (l10n.editAnswer ?? 'Edit Answer')
                                  : (l10n.writeAnswer ?? 'Write Answer'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content area
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Text field
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color.fromARGB(255, 45, 43, 61)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: CupertinoTextField(
                                  controller: controller,
                                  placeholder: l10n.writeAnswerPlaceholder ??
                                      'Write your answer here...',
                                  placeholderStyle: TextStyle(
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[500],
                                  ),
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  maxLines: 4,
                                  minLines: 3,
                                  maxLength: 500,
                                  decoration: const BoxDecoration(
                                    border: Border(),
                                  ),
                                  cursorColor:
                                      isDark ? Colors.white : Colors.black,
                                  enabled:
                                      !isSubmitting, // Disable when submitting
                                ),
                              ),

                              const SizedBox(height: 8),

                              // Character counter
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${controller.text.length}/500',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: controller.text.length > 450
                                        ? Colors.orange
                                        : (isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600]),
                                    fontWeight: controller.text.length > 450
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom buttons
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: CupertinoButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.of(ctx).pop(),
                                child: Text(
                                  l10n.cancel ?? 'Cancel',
                                  style: TextStyle(
                                    color: isSubmitting
                                        ? CupertinoColors.inactiveGray
                                        : CupertinoColors.destructiveRed,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CupertinoButton(
                                color: (controller.text.trim().isEmpty ||
                                        isSubmitting)
                                    ? CupertinoColors.inactiveGray
                                    : const Color(0xFF00A86B),
                                onPressed: (controller.text.trim().isEmpty ||
                                        isSubmitting)
                                    ? null
                                    : () async {
                                        final ans = controller.text.trim();
                                        if (ans.isEmpty) return;

                                        setDialogState(() {
                                          isSubmitting = true;
                                        });

                                        try {
                                          // Fetch shop data for answerer details
                                          final shopDoc =
                                              await FirebaseFirestore.instance
                                                  .collection('shops')
                                                  .doc(widget.shopId)
                                                  .get();
                                          final shopData = shopDoc.data() ?? {};
                                          final shopName =
                                              shopData['name'] as String? ??
                                                  'Anonymous';
                                          final shopImage =
                                              shopData['profileImageUrl']
                                                      as String? ??
                                                  '';

                                          await doc.update({
  'answerText': ans,
  'answered': true,
  'answererName': shopName,
  'answererProfileImage': shopImage,
  'answeredAt': FieldValue.serverTimestamp(),
});

// Get question data for notification
final questionDoc = await doc.get();
final questionData = questionDoc.data() as Map<String, dynamic>?;

if (questionData != null) {
  final askerId = questionData['askerId'] as String?;
  final productName = questionData['productName'] as String? ?? '';
  final productId = questionData['productId'] as String?;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Create notification (fire and forget - don't block on failure)
  if (askerId != null && askerId.isNotEmpty && askerId != currentUserId) {
    FirebaseFirestore.instance
        .collection('users')
        .doc(askerId)
        .collection('notifications')
        .add({
      'type': 'product_question_answered',
      'userId': askerId,
      'message': '🎉 Your question about "$productName" has been answered!',
      'messageEn': '🎉 Your question about "$productName" has been answered!',
      'messageTr': '🎉 "$productName" hakkındaki sorunuz yanıtlandı!',
      'messageRu': '🎉 На ваш вопрос о "$productName" ответили!',
      'productId': productId,
      'productName': productName,
      'shopId': widget.shopId,
      'shopName': shopName,
      'answerPreview': ans.length > 100 ? '${ans.substring(0, 100)}...' : ans,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    }).catchError((e) {
      // Log but don't block - answer was saved successfully
      debugPrint('Failed to create notification: $e');
    });
  }
}

if (ctx.mounted) {
  Navigator.of(ctx).pop();
}

                                          // Move question from unanswered to answered tab
                                          _moveQuestionToAnswered(
                                              doc.id, ans, shopName, shopImage);
                                        } catch (e) {
                                          debugPrint(
                                              'Error updating answer: $e');

                                          setDialogState(() {
                                            isSubmitting = false;
                                          });

                                          // Optionally show error to user
                                          if (ctx.mounted) {
                                            showCupertinoDialog(
                                              context: ctx,
                                              builder: (context) =>
                                                  CupertinoAlertDialog(
                                                title:
                                                    Text(l10n.error ?? 'Error'),
                                                content: Text(l10n.error ??
                                                    'Failed to submit answer. Please try again.'),
                                                actions: [
                                                  CupertinoDialogAction(
                                                    child:
                                                        Text(l10n.ok ?? 'OK'),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        }
                                      },
                                child: isSubmitting
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.send_rounded,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            l10n.sendAnswer ?? 'Send Answer',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Move question from unanswered to answered tab immediately
  void _moveQuestionToAnswered(
      String docId, String answerText, String shopName, String shopImage) {
    setState(() {
      // Remove from unanswered list
      _unansweredDocs.removeWhere((doc) => doc.id == docId);

      // Clear and refresh answered list
      _answeredDocs.clear();
      _answeredLastDoc = null;
      _answeredHasMore = true;

      // Switch to answered tab
      _tabController.animateTo(1);
    });

    // Fetch the updated answered list from Firestore
    _fetchAnsweredPage();
  }

  Future<void> _showDeleteDialog(
      BuildContext context, DocumentReference doc) async {
    final l10n = AppLocalizations.of(context);

    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteQuestion ?? 'Delete Question'),
        content: Text(l10n.deleteQuestionConfirmation ??
            'Are you sure you want to delete this question?'),
        actions: [
          CupertinoDialogAction(
            child: Text(l10n.cancel ?? 'Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: Text(l10n.delete ?? 'Delete'),
            onPressed: () async {
              try {
                await doc.delete();
                Navigator.of(ctx).pop();

                // Remove from local list immediately
                setState(() {
                  _unansweredDocs.removeWhere((d) => d.id == doc.id);
                  _answeredDocs.removeWhere((d) => d.id == doc.id);
                });
              } catch (e) {
                debugPrint('Error deleting question: $e');
              }
            },
          ),
        ],
      ),
    );
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
        _unansweredDocs.clear();
        _unansweredLastDoc = null;
        _unansweredHasMore = true;
        _answeredDocs.clear();
        _answeredLastDoc = null;
        _answeredHasMore = true;
      });
      await _fetchUnansweredPage();
      await _fetchAnsweredPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

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
          l10n.productQuestions ?? 'Product Questions',
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
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildQuestionList(
                      _unansweredDocs,
                      _unansweredLoading,
                      _unansweredController,
                      answered: false,
                      isInitialLoad: _isInitialLoadUnanswered,
                    ),
                    _buildQuestionList(
                      _answeredDocs,
                      _answeredLoading,
                      _answeredController,
                      answered: true,
                      isInitialLoad: _isInitialLoadAnswered,
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

  /// Builds shimmer placeholder for question list
  Widget _buildQuestionsShimmer(bool isDarkMode) {
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
        padding: const EdgeInsets.only(top: 8.0),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 0),
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
                  // Question text shimmer
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: 150,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Buttons shimmer
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool loading,
    ScrollController controller, {
    required bool answered,
    required bool isInitialLoad,
  }) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final questionBg = isDarkMode
        ? const Color.fromARGB(255, 54, 50, 75)
        : const Color(0xFFF3F3F3);
    final answerBg = isDarkMode ? const Color(0xFF1C1A29) : Colors.white;

    // Show shimmer during initial load
    if (isInitialLoad) {
      return _buildQuestionsShimmer(isDarkMode);
    }

    if (docs.isEmpty && !loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/questions.png', width: 140),
            const SizedBox(height: 12),
            Text(
              l10n.noQuestions,
              style: GoogleFonts.inter(
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
      padding: const EdgeInsets.only(top: 8.0),
      itemCount: docs.length + (loading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index >= docs.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = docs[index];
        final data = doc.data();

        final productImage = data['productImage'] as String? ?? '';
        final productName = data['productName'] as String? ?? '';
        final productPrice = data['productPrice'] as num? ?? 0;
        final productRating =
            (data['productRating'] as num?)?.toDouble() ?? 0.0;
        final questionText = data['questionText'] as String? ?? '';
        final askerName = data['askerNameVisible'] == true
            ? (data['askerName'] as String? ?? '')
            : 'Anonim';

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 33, 31, 49)
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
                GestureDetector(
                  onTap: () =>
                      context.push('/product/${data['productId']}'),
                  child: ProductCard4(
                    imageUrl: productImage,
                    colorImages: const {},
                    productName: productName,
                    brandModel: '',
                    price: productPrice.toDouble(),
                    currency: '',
                    averageRating: productRating,
                    showOverlayIcons: false,
                    isShopProduct: true,
                  ),
                ),
                const SizedBox(height: 8),
                if (!answered) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: questionBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionText,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.askedBy ?? "Asked by"}: $askerName',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hide Reply and Delete buttons for viewers
                  if (!_isViewer) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showAnswerDialog(context, doc.reference),
                            icon: const Icon(Icons.reply, size: 18),
                            label: Text(
                              l10n.answer ?? 'Answer',
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'Figtree',
                                fontWeight: FontWeight.w600,
                              ),
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
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showDeleteDialog(context, doc.reference),
                            icon: const Icon(Icons.delete, size: 18),
                            label: Text(
                              l10n.delete ?? 'Delete',
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'Figtree',
                                fontWeight: FontWeight.w600,
                              ),
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
                  ],
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: questionBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          questionText,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Soran: $askerName',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: answerBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            data['answerText'] as String? ?? '',
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hide Edit button for viewers
                  if (!_isViewer)
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => _showAnswerDialog(context, doc.reference,
                            existingAnswer: data['answerText'] as String?),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
