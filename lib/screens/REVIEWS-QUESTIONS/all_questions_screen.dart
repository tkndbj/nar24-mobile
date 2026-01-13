import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/translation_service.dart';

class AllQuestionsScreen extends StatefulWidget {
  final String productId;
  final String sellerId;
  final bool isShop;

  const AllQuestionsScreen({
    Key? key,
    required this.productId,
    required this.sellerId,
    required this.isShop,
  }) : super(key: key);

  @override
  _AllQuestionsScreenState createState() => _AllQuestionsScreenState();
}

class _AllQuestionsScreenState extends State<AllQuestionsScreen> {
  static const int _pageSize = 20;
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');

  final ScrollController _scrollController = ScrollController();
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  late final String _baseColl;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _sellerFuture;

  late Color _containerBg;
  late Color _questionBg;
  late Color _answerBg;
  late bool _isDark;

  @override
  void initState() {
    super.initState();

    _baseColl = widget.isShop ? 'shops' : 'users';
    _sellerFuture = FirebaseFirestore.instance
        .collection(_baseColl)
        .doc(widget.sellerId)
        .get();

    _scrollController.addListener(_onScroll);
    _fetchNextPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _fetchNextPage();
    }
  }

  Future<void> _fetchNextPage() async {
    if (!_hasMore) return;
    setState(() => _isLoading = true);

    // 1️⃣ One single collectionGroup query across both products & shop_products:
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collectionGroup('product_questions')
        .where('productId', isEqualTo: widget.productId)
        .where('answered', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(_pageSize);

    // 2️⃣ Apply pagination cursor only if _lastDoc exists
    if (_lastDoc != null) {
      q = q.startAfterDocument(_lastDoc!);
    }

    // 3️⃣ Fire off the query
    final snap = await q.get();
    final newDocs = snap.docs;

    // 4️⃣ Update pagination state
    if (newDocs.length < _pageSize) _hasMore = false;
    if (newDocs.isNotEmpty) _lastDoc = newDocs.last;

    // 5️⃣ Merge into our list and refresh
    setState(() {
      _docs.addAll(newDocs);
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _isDark = Theme.of(context).brightness == Brightness.dark;
    _containerBg = _isDark
        ? const Color.fromARGB(255, 54, 50, 75)
        : const Color.fromARGB(255, 240, 240, 240);
    _questionBg = _isDark ? const Color(0xFF1C1A29) : const Color(0xFFF3F3F3);
    _answerBg = _isDark ? const Color(0xFF1C1A29) : Colors.white;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor:
            _isDark ? Theme.of(context).dividerColor : Colors.grey.shade300,
      ),
      child: Scaffold(
        backgroundColor: _containerBg,
        appBar: AppBar(
          backgroundColor: !_isDark ? Colors.white : null,
          foregroundColor: !_isDark ? Colors.black : null,
          elevation: 2,
          shadowColor: !_isDark ? Colors.black.withOpacity(0.4) : null,
          title: Text(
            l10n.allQuestionsTitle,
            style: !_isDark ? const TextStyle(color: Colors.black) : null,
          ),
          iconTheme: !_isDark ? const IconThemeData(color: Colors.black) : null,
        ),
        body: SafeArea(
          child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _sellerFuture,
            builder: (context, sellerSnap) {
              if (sellerSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!sellerSnap.hasData || !sellerSnap.data!.exists) {
                return Center(child: Text(l10n.errorLoadingSeller));
              }

              final sellerData = sellerSnap.data!.data()!;
              final sellerImageUrl = widget.isShop
                  ? sellerData['profileImageUrl'] as String?
                  : sellerData['profileImage'] as String?;
              final sellerName = widget.isShop
                  ? (sellerData['name'] as String? ?? l10n.anonymous)
                  : (sellerData['displayName'] as String? ??
                      l10n.anonymous); // Fix: Use displayName for users

              if (_docs.isEmpty && !_hasMore && !_isLoading) {
                return Center(child: Text(l10n.noQuestionsFound));
              }

              return ListView.separated(
                controller: _scrollController,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemCount: _docs.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _docs.length) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final doc = _docs[i];
                  return QuestionTile(
                    key: ValueKey('question_${doc.id}'),
                    data: doc.data(),
                    timestamp:
                        (doc.data()['timestamp'] as Timestamp?)?.toDate(),
                    askerId: doc.data()['askerId'] as String? ?? '',
                    sellerImageUrl: sellerImageUrl,
                    sellerName: sellerName,
                    isShop: widget.isShop,
                    questionBg: _questionBg,
                    answerBg: _answerBg,
                    dateFmt: _dateFmt,
                    l10n: l10n,
                    questionId: doc.id,
                  );
                },
              );
            },
          ),
        ),
        persistentFooterButtons: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context.push(
                      '/ask_to_seller',
                      extra: {
                        'productId': widget.productId,
                        'sellerId': widget.sellerId,
                        'isShop': widget.isShop,
                      },
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: Text(
                    l10n.askToSeller,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: Text(
                    l10n.addToCart,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QuestionTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final DateTime? timestamp;
  final String askerId;
  final String? sellerImageUrl;
  final String sellerName;
  final bool isShop;
  final Color questionBg;
  final Color answerBg;
  final DateFormat dateFmt;
  final AppLocalizations l10n;
  final String questionId; // ADD THIS

  const QuestionTile({
    Key? key,
    required this.data,
    this.timestamp,
    required this.askerId,
    required this.sellerImageUrl,
    required this.sellerName,
    required this.isShop,
    required this.questionBg,
    required this.answerBg,
    required this.dateFmt,
    required this.l10n,
    required this.questionId, // ADD THIS
  }) : super(key: key);

  @override
  State<QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<QuestionTile> {
  bool _isTranslated = false;
  String _translatedQuestion = '';
  String _translatedAnswer = '';
  bool _isTranslating = false;

 Future<void> _toggleTranslation(String questionText, String answerText) async {
  if (_isTranslated) {
    setState(() {
      _isTranslated = false;
    });
    return;
  }

  final userLocale = Localizations.localeOf(context).languageCode;
  final translationService = TranslationService();

  // Check if already cached in TranslationService
  final cachedQuestion = translationService.getCached(questionText, userLocale);
  final cachedAnswer = translationService.getCached(answerText, userLocale);

  if (cachedQuestion != null && cachedAnswer != null) {
    setState(() {
      _translatedQuestion = cachedQuestion;
      _translatedAnswer = cachedAnswer;
      _isTranslated = true;
    });
    return;
  }

  setState(() {
    _isTranslating = true;
  });

  try {
    final translations = await translationService.translateBatch(
      [questionText, answerText],
      userLocale,
    );

    setState(() {
      _translatedQuestion = translations[0];
      _translatedAnswer = translations[1];
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
        SnackBar(content: Text('Error translating: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        widget.timestamp == null ? '' : widget.dateFmt.format(widget.timestamp!);
    final questionText = widget.data['questionText'] as String? ?? '';
    final answerText = widget.data['answerText'] as String? ?? '';
    final askerName = (widget.data['askerNameVisible'] == true)
        ? widget.data['askerName'] as String? ?? widget.l10n.anonymous
        : widget.l10n.anonymous;
    final answered = widget.data['answered'] as bool? ?? false;
    final answererName = widget.data['answererName'] as String? ??
        widget.sellerName; // Fallback to sellerName
    final answererImage = widget.data['answererProfileImage'] as String? ??
        widget.sellerImageUrl; // Fallback to sellerImageUrl
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconTextColor =
        isDark ? Colors.white : const Color.fromRGBO(0, 0, 0, 0.6);

    // Use translated text if available
    final displayQuestion = _isTranslated ? _translatedQuestion : questionText;
    final displayAnswer = _isTranslated ? _translatedAnswer : answerText;

    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.questionBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  askerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayQuestion,
                  style: const TextStyle(fontSize: 14),
                ),
                if (answered) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.answerBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.grey[200],
                          backgroundImage:
                              answererImage != null && answererImage.isNotEmpty
                                  ? CachedNetworkImageProvider(answererImage)
                                  : null,
                          child: answererImage == null || answererImage.isEmpty
                              ? const Icon(Icons.person, size: 16)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                answererName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayAnswer,
                                style: const TextStyle(fontSize: 14),
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
          const SizedBox(height: 8),
          // Translation button
          Row(
            children: [
              GestureDetector(
                onTap: _isTranslating
                    ? null
                    : () => _toggleTranslation(questionText, answerText),
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
                    : () => _toggleTranslation(questionText, answerText),
                child: Text(
                  _isTranslated ? widget.l10n.seeOriginal : widget.l10n.translate,
                  style: TextStyle(
                    fontSize: 12,
                    color: iconTextColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_isTranslating)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}