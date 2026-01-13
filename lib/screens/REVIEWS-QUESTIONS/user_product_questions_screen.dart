import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/product_card_4.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class UserProductQuestionsScreen extends StatefulWidget {
  const UserProductQuestionsScreen({Key? key}) : super(key: key);

  @override
  _UserProductQuestionsScreenState createState() =>
      _UserProductQuestionsScreenState();
}

class _UserProductQuestionsScreenState extends State<UserProductQuestionsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;
  static const Color jadeGreen = Color(0xFF00A86B);
  late final TabController _tabController;
  late final ScrollController _askedController;
  late final ScrollController _receivedController;

  String? _currentProductFilter;
  String? _currentSellerFilter; // For first tab only
  DateTime? _currentStartDate;
  DateTime? _currentEndDate;

  bool _showAnsweredOnly = false;

  // Asked pagination
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _askedDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _askedLastDoc;
  bool _askedHasMore = true;
  bool _askedLoading = false;
  bool _askedInitialLoading = true;

  // Received pagination
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _receivedDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _receivedLastDoc;
  bool _receivedHasMore = true;
  bool _receivedLoading = false;
  bool _receivedInitialLoading = true;

  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;

    _tabController = TabController(length: 2, vsync: this);

    _askedController = ScrollController()..addListener(_askedOnScroll);
    _receivedController = ScrollController()..addListener(_receivedOnScroll);

    if (_uid != null) {
      _fetchAskedPage();
      _fetchReceivedPage();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _askedController.dispose();
    _receivedController.dispose();
    super.dispose();
  }

  void _askedOnScroll() {
    if (_askedController.position.pixels >=
            _askedController.position.maxScrollExtent - 100 &&
        !_askedLoading &&
        _askedHasMore) {
      _fetchAskedPage();
    }
  }

  void _receivedOnScroll() {
    if (_receivedController.position.pixels >=
            _receivedController.position.maxScrollExtent - 100 &&
        !_receivedLoading &&
        _receivedHasMore) {
      _fetchReceivedPage();
    }
  }

  Future<void> _fetchAskedPage() async {
    if (!_askedHasMore || _askedLoading || _uid == null) return;
    setState(() => _askedLoading = true);

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collectionGroup('product_questions')
          .where('askerId', isEqualTo: _uid);

      // ✅ Apply seller filter SERVER-SIDE
      if (_currentSellerFilter != null) {
        query = query.where('sellerId', isEqualTo: _currentSellerFilter);
      }

      // Apply product filter if set
      if (_currentProductFilter != null) {
        query = query.where('productId', isEqualTo: _currentProductFilter);
      }

      // Apply date filters if set
      if (_currentStartDate != null) {
        query = query.where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!),
        );
      }
      if (_currentEndDate != null) {
        final endOfDay = DateTime(_currentEndDate!.year, _currentEndDate!.month,
            _currentEndDate!.day, 23, 59, 59);
        query = query.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        );
      }

      // Apply answered filter if set
      if (_showAnsweredOnly) {
        query = query.where('answered', isEqualTo: true);
      }

      query = query.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_askedLastDoc != null) {
        query = query.startAfterDocument(_askedLastDoc!);
      }

      final snap = await query.get();
      final newDocs = snap.docs; // ✅ No client-side filtering needed

      if (newDocs.length < _pageSize) _askedHasMore = false;
      if (newDocs.isNotEmpty) _askedLastDoc = newDocs.last;

      if (mounted) {
        setState(() {
          _askedDocs.addAll(newDocs);
          _askedLoading = false;
          _askedInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching asked questions: $e');
      if (mounted) {
        setState(() {
          _askedLoading = false;
          _askedInitialLoading = false;
        });
      }
    }
  }

  Future<void> _fetchReceivedPage() async {
    if (!_receivedHasMore || _receivedLoading || _uid == null) return;
    setState(() => _receivedLoading = true);

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collectionGroup('product_questions')
          .where('sellerId', isEqualTo: _uid);

      // Apply product filter if set
      if (_currentProductFilter != null) {
        query = query.where('productId', isEqualTo: _currentProductFilter);
      }

      // Apply date filters if set
      if (_currentStartDate != null) {
        query = query.where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_currentStartDate!),
        );
      }
      if (_currentEndDate != null) {
        final endOfDay = DateTime(_currentEndDate!.year, _currentEndDate!.month,
            _currentEndDate!.day, 23, 59, 59);
        query = query.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        );
      }

      // Apply answered filter if set
      if (_showAnsweredOnly) {
        query = query.where('answered', isEqualTo: true);
      }

      query = query.orderBy('timestamp', descending: true).limit(_pageSize);

      if (_receivedLastDoc != null) {
        query = query.startAfterDocument(_receivedLastDoc!);
      }

      final snap = await query.get();
      final newDocs = snap.docs;

      if (newDocs.length < _pageSize) _receivedHasMore = false;
      if (newDocs.isNotEmpty) _receivedLastDoc = newDocs.last;

      if (mounted) {
        setState(() {
          _receivedDocs.addAll(newDocs);
          _receivedLoading = false;
          _receivedInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching received questions: $e');
      if (mounted) {
        setState(() {
          _receivedLoading = false;
          _receivedInitialLoading = false;
        });
      }
    }
  }

 Future<void> _showAnswerDialog(BuildContext context, DocumentReference doc,
    {String? existingAnswer}) async {
  final controller = TextEditingController(text: existingAnswer);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final l10n = AppLocalizations.of(context);

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00A86B), Color(0xFF00C574)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.reply,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      existingAnswer != null ? l10n.editAnswer : l10n.replyToQuestion,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: controller,
                maxLines: 5,
                autofocus: true,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: l10n.writeYourAnswer,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey,
                    fontSize: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF00A86B),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1C1A29)
                      : Colors.grey.shade50,
                ),
              ),
            ),
            // Footer with buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        l10n.cancel,
                        style: TextStyle(
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        final ans = controller.text.trim();
                        if (ans.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.pleaseEnterAnAnswer),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        try {
                          // Show loading
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color.fromARGB(255, 33, 31, 49)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF00A86B),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      l10n.submittingAnswer,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );

                          final userDoc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(_uid)
                              .get();
                          final userData = userDoc.data() ?? {};

                          final displayName = userData['displayName'] as String? ?? '';
                          final profileImage = userData['profileImage'] as String? ?? '';

                          await doc.update({
  'answerText': ans,
  'answered': true,
  'answererName': displayName,
  'answererProfileImage': profileImage,
  'answeredAt': FieldValue.serverTimestamp(),
});

// Get question data for notification
final questionDoc = await doc.get();
final questionData = questionDoc.data() as Map<String, dynamic>?;

if (questionData != null) {
  final askerId = questionData['askerId'] as String?;
  final productName = questionData['productName'] as String? ?? '';
  final productId = questionData['productId'] as String?;

  // Create notification for the asker (don't notify yourself)
if (askerId != null && askerId.isNotEmpty && askerId != _uid) {
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
    'answererName': displayName,
    'answerPreview': ans.length > 100 ? '${ans.substring(0, 100)}...' : ans,
    'timestamp': FieldValue.serverTimestamp(),
    'isRead': false,
  }).catchError((e) {
    // Log but don't block - answer was saved successfully
    debugPrint('Failed to create notification: $e');
  });
}
}

if (mounted) {
  Navigator.of(context).pop(); // Close loading
  Navigator.of(context).pop(); // Close dialog
                            
                            // Show success message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Text(l10n.answerSubmittedSuccessfully),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF00A86B),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                margin: const EdgeInsets.all(16),
                              ),
                            );

                            // Refresh the list
                            setState(() {
                              _receivedDocs.clear();
                              _receivedLastDoc = null;
                              _receivedHasMore = true;
                            });
                            _fetchReceivedPage();
                          }
                        } catch (e) {
                          debugPrint('Error updating answer: $e');
                          if (mounted) {
                            Navigator.of(context).pop(); // Close loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${l10n.error}: ${e.toString()}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            l10n.send,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
  );
}

  Future<void> _showDeleteDialog(
      BuildContext context, DocumentReference doc) async {
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Soruyu Sil'),
        content: const Text('Bu soruyu silmek istediğinizden emin misiniz?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('İptal'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Sil'),
            onPressed: () async {
              try {
                await doc.delete();
                Navigator.of(ctx).pop();
              } catch (e) {
                debugPrint('Error deleting question: $e');
              }
            },
          ),
        ],
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
          _buildModernTab(
              l10n.askedQuestionsTabLabel, Icons.question_answer_rounded),
          _buildModernTab(l10n.receivedQuestionsTabLabel, Icons.inbox_rounded),
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

  Widget _buildQuestionList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool loading,
    ScrollController controller, {
    required bool isAskedTab,
    required bool initialLoading,
  }) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final questionBg = isDarkMode
        ? const Color.fromARGB(255, 54, 50, 75)
        : const Color(0xFFF3F3F3);
    final answerBg = isDarkMode ? const Color(0xFF1C1A29) : Colors.white;

    // Show shimmer for initial loading
    if (initialLoading) {
      return _buildShimmerList(isDarkMode);
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
          return _buildQuestionShimmerItem(isDarkMode);
        }
        final doc = docs[index];
        final data = doc.data();
        final answererImage = data['answererProfileImage'] as String? ?? '';
        final answererName = data['answererName'] as String? ?? '';
        final productImage = data['productImage'] as String? ?? '';
        final productName = data['productName'] as String? ?? '';
        final productPrice = (data['productPrice'] as num?)?.toDouble() ?? 0;
        final productRating =
            (data['productRating'] as num?)?.toDouble() ?? 0.0;
        final questionText = data['questionText'] as String? ?? '';
        final answered = data['answered'] as bool? ?? false;
        final answerText = data['answerText'] as String? ?? '';
        final askerName = data['askerNameVisible'] == true
            ? (data['askerName'] as String? ?? '')
            : 'Anonim';

        final parentId = doc.reference.parent.parent?.id;
        final isShopProduct = parentId == 'shops';

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
                    price: productPrice,
                    currency: '',
                    averageRating: productRating,
                    showOverlayIcons: false,
                    isShopProduct: isShopProduct,
                  ),
                ),
                const SizedBox(height: 8),
                if (isAskedTab) ...[
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
                        if (answered) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: answerBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                if (answererImage.isNotEmpty)
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage:
                                        NetworkImage(answererImage),
                                  ),
                                if (answererImage.isNotEmpty)
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (answererName.isNotEmpty)
                                        Text(
                                          answererName,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      Text(
                                        answerText,
                                        style: GoogleFonts.inter(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!answered) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.waitingForAnswer,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
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
                        if (answered) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: answerBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              answerText,
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!answered) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showAnswerDialog(context, doc.reference),
                            icon: const Icon(Icons.reply, size: 18),
                            label: Text(
                              'Cevapla',
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
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showDeleteDialog(context, doc.reference),
                            icon: const Icon(Icons.delete, size: 18),
                            label: Text(
                              'Sil',
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
                  ] else ...[
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () => _showAnswerDialog(context, doc.reference,
                            existingAnswer: answerText),
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
              ],
            ),
          ),
        );
      },
    );
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
        _askedDocs.clear();
        _askedLastDoc = null;
        _askedHasMore = true;
        _askedInitialLoading = true;
        _receivedDocs.clear();
        _receivedLastDoc = null;
        _receivedHasMore = true;
        _receivedInitialLoading = true;
      });
      await _fetchAskedPage();
      await _fetchReceivedPage();
    }
  }

  Widget _buildQuestionShimmerItem(bool isDark) {
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
                height: 80,
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
      itemBuilder: (_, __) => _buildQuestionShimmerItem(isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Handle case where user is not logged in
    if (_uid == null) {
      return Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF1C1A29)
            : const Color.fromARGB(255, 235, 235, 235),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: isDark ? null : Colors.white,
          title: Text(
            l10n.userQuestionsTitle,
            style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
        body: Center(
          child: Text(
            l10n.notLoggedIn,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1A29)
          : const Color.fromARGB(255, 235, 235, 235),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? null : Colors.white,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        title: Text(
          l10n.userQuestionsTitle,
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
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1A29)
              : const Color.fromARGB(255, 233, 233, 233),
        ),
        child: SafeArea(
          bottom: true,
          child: Column(
            children: [
              _buildModernTabBar(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 160,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _showAnsweredOnly
                            ? Colors.orange
                            : Colors.transparent,
                        side: BorderSide(
                          color: _showAnsweredOnly
                              ? Colors.orange
                              : (isDark ? Colors.grey.shade600 : Colors.grey.shade500),
                          width: 1.2,
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        l10n.answered,
                        style: TextStyle(
                          color: _showAnsweredOnly
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _showAnsweredOnly = !_showAnsweredOnly;
                          _askedDocs.clear();
                          _askedLastDoc = null;
                          _askedHasMore = true;
                          _askedInitialLoading = true;
                          _receivedDocs.clear();
                          _receivedLastDoc = null;
                          _receivedHasMore = true;
                          _receivedInitialLoading = true;
                        });
                        _fetchAskedPage();
                        _fetchReceivedPage();
                      },
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildQuestionList(
                      _askedDocs,
                      _askedLoading,
                      _askedController,
                      isAskedTab: true,
                      initialLoading: _askedInitialLoading,
                    ),
                    _buildQuestionList(
                      _receivedDocs,
                      _receivedLoading,
                      _receivedController,
                      isAskedTab: false,
                      initialLoading: _receivedInitialLoading,
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
}
