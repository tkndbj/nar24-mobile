import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/review_dialog_view_model.dart';
import 'dart:io';

const int _kMaxReviewImages = 3;
const int _kMinReviewChars = 5;

class ReviewDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final bool isProduct;
  final bool isShopProduct;
  final String? productId;
  final String? sellerId;
  final String? shopId;
  final String? transactionId;
  final String collectionPath;
  final String docId;
  final String storagePath;
  final bool isDarkMode;
  final ReviewDialogViewModel viewModel;
  final BuildContext parentContext;
  final VoidCallback onReviewSubmitted;
  final double? initialRating;
  final String? initialReviewText;
  final List<String>? initialImageUrls;
  final String? orderId;

  const ReviewDialog({
    Key? key,
    required this.l10n,
    required this.isProduct,
    required this.isShopProduct,
    this.productId,
    this.sellerId,
    this.shopId,
    this.transactionId,
    required this.collectionPath,
    required this.docId,
    required this.storagePath,
    required this.isDarkMode,
    required this.viewModel,
    required this.parentContext,
    required this.onReviewSubmitted,
    this.initialRating,
    this.initialReviewText,
    this.initialImageUrls,
    this.orderId,
  }) : super(key: key);

  @override
  _ReviewDialogState createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final TextEditingController _reviewController = TextEditingController();
  bool _submitting = false;
  List<String> _initialImageUrls = [];

  @override
  void initState() {
    super.initState();
    // Initialize rating and review text from widget parameters
    if (widget.initialRating != null) {
      widget.viewModel.rating = widget.initialRating!;
    }
    if (widget.initialReviewText != null) {
      widget.viewModel.reviewText = widget.initialReviewText!;
      _reviewController.text = widget.initialReviewText!;
    }
    if (widget.initialImageUrls != null) {
      _initialImageUrls = widget.initialImageUrls!;
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      widget.viewModel.rating > 0 &&
      widget.viewModel.reviewText.trim().length >= _kMinReviewChars;

  /// Handle submit - immediately close modal and trigger async submission
  void _handleSubmit() {
    if (_submitting || !_canSubmit) return;

    setState(() => _submitting = true);

    // Immediately close the review dialog
    Navigator.of(context).pop(true);

    // Call the callback to trigger the loading modal and submission process
    widget.onReviewSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final l10n = widget.l10n;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final canSubmit = _canSubmit && !_submitting;
    const accent = Color(0xFF00A86B);

    Future<void> pickImage() async {
      if ((_initialImageUrls.length +
              widget.viewModel.selectedImages.length) >=
          _kMaxReviewImages) {
        return;
      }
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (img != null) {
        setState(() =>
            widget.viewModel.selectedImages.add(File(img.path)));
      }
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85 -
                    MediaQuery.of(context).viewInsets.bottom,
                maxWidth: isTablet ? 500 : double.infinity,
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
                            color: accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.isProduct
                                ? Icons.shopping_bag_rounded
                                : Icons.storefront_rounded,
                            color: accent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.isProduct
                                ? l10n.productReview
                                : l10n.sellerReview,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
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
                          // Stars
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              5,
                              (idx) => GestureDetector(
                                onTap: () => setState(
                                    () => widget.viewModel.rating = idx + 1),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    idx < widget.viewModel.rating
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
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: CupertinoTextField(
                              controller: _reviewController,
                              placeholder: l10n.pleaseEnterYourReview,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              style: TextStyle(
                                color:
                                    isDark ? Colors.white : Colors.black87,
                                fontSize: 14,
                              ),
                              cursorColor:
                                  isDark ? Colors.white : Colors.black,
                              maxLines: 4,
                              decoration:
                                  const BoxDecoration(border: Border()),
                              onChanged: (v) => setState(
                                  () => widget.viewModel.reviewText = v),
                            ),
                          ),

                          // Photo upload section (only for products)
                          if (widget.isProduct) ...[
                            const SizedBox(height: 16),
                            Text(
                              l10n.photosOptionalUpTo('$_kMaxReviewImages'),
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
                                // Already-uploaded thumbnails
                                ..._initialImageUrls.map(
                                  (url) => Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: Image.network(
                                        url,
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                // Newly picked local files
                                ...widget.viewModel.selectedImages.map(
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
                                            onTap: () => setState(() => widget
                                                .viewModel.selectedImages
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
                                if ((_initialImageUrls.length +
                                        widget.viewModel.selectedImages
                                            .length) <
                                    _kMaxReviewImages)
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
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                l10n.cancel,
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoButton(
                              color: canSubmit
                                  ? accent
                                  : CupertinoColors.inactiveGray,
                              onPressed: canSubmit ? _handleSubmit : null,
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
  }
}
