import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../services/translation_service.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../providers/product_detail_provider.dart';
import 'package:shimmer/shimmer.dart';

class ProductQuestionsWidget extends StatefulWidget {
  final String productId;
  final String sellerId;
  final bool isShop;

  const ProductQuestionsWidget({
    Key? key,
    required this.productId,
    required this.sellerId,
    required this.isShop,
  }) : super(key: key);

  @override
  _ProductQuestionsWidgetState createState() => _ProductQuestionsWidgetState();
}

class _ProductQuestionsWidgetState extends State<ProductQuestionsWidget>
    with AutomaticKeepAliveClientMixin {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _sellerFuture;
  late final Future<List<Map<String, dynamic>>> _questionsFuture;

  @override
  void initState() {
    super.initState();
    final sellerColl = widget.isShop ? 'shops' : 'users';
    final questionColl = widget.isShop ? 'shop_products' : 'products';

    _sellerFuture = FirebaseFirestore.instance
        .collection(sellerColl)
        .doc(widget.sellerId)
        .get();

    _questionsFuture =
        Provider.of<ProductDetailProvider>(context, listen: false)
            .getProductQuestions(
      widget.productId,
      questionColl,
    );
  }

  // Determine if current device is a tablet
  bool _isTablet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final orientation = mediaQuery.orientation;

    final shortestSide =
        orientation == Orientation.portrait ? screenWidth : screenHeight;
    return shortestSide >= 600 ||
        (orientation == Orientation.landscape && screenWidth >= 900);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg =
        isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white;
    final questionBg =
        isDark ? const Color(0xFF1C1A29) : const Color(0xFFF3F3F3);
    final answerBg =
        isDark ? const Color.fromARGB(255, 54, 50, 75) : Colors.white;

    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = _isTablet(context);

    // Responsive sizing
    final double itemWidth;
    if (isTablet) {
      itemWidth = screenWidth > 1200 ? 320 : 280;
    } else {
      itemWidth = screenWidth * 0.8 < 260 ? screenWidth * 0.8 : 260;
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _sellerFuture,
      builder: (context, sellerSnap) {
        if (!sellerSnap.hasData) return const SizedBox.shrink();
        final sellerData = sellerSnap.data!.data() ?? {};
        final sellerImageUrl = widget.isShop
            ? sellerData['profileImageUrl'] as String?
            : sellerData['profileImage'] as String?;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _questionsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            if (!snap.hasData || snap.hasError) {
              return const SizedBox.shrink();
            }
            final questions = snap.data!;
            if (questions.isEmpty) return const SizedBox.shrink();

            // Responsive heights
            final double containerHeight = isTablet ? 240 : 200;

            return Container(
              width: double.infinity,
              color: containerBg,
              padding: EdgeInsets.symmetric(
                vertical: isTablet ? 20 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // header
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 20 : 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.productQuestionsHeader,
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            context.pushNamed(
                              'allQuestions',
                              pathParameters: {
                                'productId': widget.productId,
                                'sellerId': widget.sellerId,
                                'isShop': widget.isShop.toString(),
                              },
                            );
                          },
                          child: Text(
                            l10n.viewAllQuestions(questions.length),
                            style: TextStyle(
                              fontSize: isTablet ? 15 : 14,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isTablet ? 16 : 12),
                  // horizontal list
                  SizedBox(
                    height: containerHeight,
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 20 : 16,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: questions.length,
                      separatorBuilder: (_, __) => SizedBox(
                        width: isTablet ? 16 : 12,
                      ),
                      itemBuilder: (context, i) {
                        final data = questions[i];
                        return _QuestionAnswerCard(
                          key: ValueKey('question_card_${data['questionId']}'),
                          data: data,
                          itemWidth: itemWidth,
                          containerHeight: containerHeight,
                          sellerImageUrl: sellerImageUrl,
                          isTablet: isTablet,
                          questionBg: questionBg,
                          answerBg: answerBg,
                          l10n: l10n,
                          productId: widget.productId,
                          sellerId: widget.sellerId,
                          isShop: widget.isShop,
                          questionId: data['questionId'],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _QuestionAnswerCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final double itemWidth;
  final double containerHeight;
  final String? sellerImageUrl;
  final bool isTablet;
  final Color questionBg;
  final Color answerBg;
  final AppLocalizations l10n;
  final String productId;
  final String sellerId;
  final bool isShop;
  final String questionId; // ADD THIS - we'll need to pass it

  const _QuestionAnswerCard({
    Key? key,
    required this.data,
    required this.itemWidth,
    required this.containerHeight,
    required this.sellerImageUrl,
    required this.isTablet,
    required this.questionBg,
    required this.answerBg,
    required this.l10n,
    required this.productId,
    required this.sellerId,
    required this.isShop,
    required this.questionId, // ADD THIS
  }) : super(key: key);

  @override
  State<_QuestionAnswerCard> createState() => _QuestionAnswerCardState();
}

class _QuestionAnswerCardState extends State<_QuestionAnswerCard> {
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
    // Use batch translation for efficiency (single API call)
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
    final questionText = widget.data['questionText'] as String? ?? '';
    final answerText = widget.data['answerText'] as String? ?? '';
    final ts = (widget.data['timestamp'] as Timestamp?)?.toDate();
    final dateLabel = ts == null ? '' : DateFormat('dd/MM/yyyy').format(ts);
    final askerName = widget.data['askerNameVisible'] == true
        ? (widget.data['askerName'] as String? ?? widget.l10n.anonymous)
        : widget.l10n.anonymous;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconTextColor =
        isDark ? Colors.white : const Color.fromRGBO(0, 0, 0, 0.6);

    // Use translated text if available
    final displayQuestion = _isTranslated ? _translatedQuestion : questionText;
    final displayAnswer = _isTranslated ? _translatedAnswer : answerText;

    // Calculate if answer is too long
    final isLongAnswer = answerText.length > (widget.isTablet ? 200 : 150);

    // Calculate available space for answer
    final double padding = widget.isTablet ? 16 : 12;
    final double headerHeight = widget.isTablet ? 70 : 60;
    final double answerContainerPadding = widget.isTablet ? 12 : 8;
    final double avatarSize = widget.isTablet ? 36 : 32;
    final double translateButtonHeight =
        widget.isTablet ? 24 : 20; // Space for translate button
    final double readAllHeight = isLongAnswer ? (widget.isTablet ? 20 : 18) : 0;

    final double availableAnswerHeight = widget.containerHeight -
        (padding * 2) -
        headerHeight -
        answerContainerPadding -
        translateButtonHeight -
        readAllHeight;

    return Container(
      width: widget.itemWidth,
      height: widget.containerHeight,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: widget.questionBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          Row(
            children: [
              const Spacer(),
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: widget.isTablet ? 13 : 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          SizedBox(height: widget.isTablet ? 10 : 8),

          // Asker name
          Text(
            askerName,
            style: TextStyle(
              fontSize: widget.isTablet ? 15 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: widget.isTablet ? 6 : 4),

          // Question text
          Text(
            displayQuestion,
            style: TextStyle(fontSize: widget.isTablet ? 15 : 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: widget.isTablet ? 14 : 12),

          // Answer box
          Expanded(
            child: Container(
              padding: EdgeInsets.all(answerContainerPadding),
              decoration: BoxDecoration(
                color: widget.answerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: avatarSize / 2,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: widget.sellerImageUrl != null
                            ? NetworkImage(widget.sellerImageUrl!)
                            : null,
                      ),
                      SizedBox(width: widget.isTablet ? 10 : 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayAnswer,
                              style: TextStyle(
                                  fontSize: widget.isTablet ? 15 : 14),
                              maxLines: widget.isTablet ? 4 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isLongAnswer) ...[
                              SizedBox(height: widget.isTablet ? 8 : 6),
                              GestureDetector(
                                onTap: () {
                                  context.pushNamed(
                                    'allQuestions',
                                    pathParameters: {
                                      'productId': widget.productId,
                                      'sellerId': widget.sellerId,
                                      'isShop': widget.isShop.toString(),
                                    },
                                  );
                                },
                                child: Text(
                                  widget.l10n.readAll,
                                  style: TextStyle(
                                    fontSize: widget.isTablet ? 14 : 13,
                                    color: iconTextColor,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Translate button at the bottom
          SizedBox(height: widget.isTablet ? 8 : 6),
          Row(
            children: [
              GestureDetector(
                onTap: _isTranslating
                    ? null
                    : () => _toggleTranslation(questionText, answerText),
                child: Icon(
                  _isTranslated ? Icons.language_outlined : Icons.language,
                  size: widget.isTablet ? 16 : 14,
                  color: iconTextColor,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _isTranslating
                    ? null
                    : () => _toggleTranslation(questionText, answerText),
                child: Text(
                  _isTranslated
                      ? widget.l10n.seeOriginal
                      : widget.l10n.translate,
                  style: TextStyle(
                    fontSize: widget.isTablet ? 14 : 12,
                    color: iconTextColor,
                  ),
                ),
              ),
              const Spacer(),
              if (_isTranslating)
                Shimmer.fromColors(
                  baseColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1C1A29)
                      : Colors.grey[300]!,
                  highlightColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color.fromARGB(255, 51, 48, 73)
                      : Colors.grey[100]!,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
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
