import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/review_dialog_view_model.dart';
import 'dart:io';

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

  /// Handle submit - immediately close modal and trigger async submission
  void _handleSubmit() {
    if (_submitting) return;

    // Validate inputs before proceeding
    if (widget.viewModel.rating == 0 || widget.viewModel.reviewText.isEmpty) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: Text(widget.l10n.pleaseProvideRatingAndReview ??
              'Please provide a rating and review text'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    // Immediately close the review dialog
    Navigator.of(context).pop(true);

    // Call the callback to trigger the loading modal and submission process
    widget.onReviewSubmitted();
  }

 @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isTablet = screenWidth >= 600;

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
        maxHeight: MediaQuery.of(context).size.height * 0.85 - MediaQuery.of(context).viewInsets.bottom,
        maxWidth: isTablet ? 500 : double.infinity,
      ),
      decoration: BoxDecoration(
        color: widget.isDarkMode
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
                    color: widget.isDarkMode 
                        ? Colors.grey.shade700 
                        : Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
              ),
              child: Text(
                widget.isProduct
                    ? widget.l10n.productReview
                    : widget.l10n.sellerReview,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            
            // Content area - this won't scroll
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        5,
                        (idx) => GestureDetector(
                          onTap: () =>
                              setState(() => widget.viewModel.rating = idx + 1),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              idx < widget.viewModel.rating
                                  ? FontAwesomeIcons.solidStar
                                  : FontAwesomeIcons.star,
                              color: Colors.amber,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Review text field
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.isDarkMode
                            ? const Color.fromARGB(255, 45, 43, 61)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.isDarkMode 
                              ? Colors.grey.shade600 
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: CupertinoTextField(
                        controller: _reviewController,
                        placeholder: widget.l10n.pleaseEnterYourReview,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        style: TextStyle(
                          color: Theme.of(widget.parentContext)
                              .colorScheme
                              .onSurface,
                          fontSize: 14,
                        ),
                        cursorColor: widget.isDarkMode ? Colors.white : Colors.black,
                        maxLines: 4, // Reduced from 5 to save space
                        decoration: const BoxDecoration(
                          border: Border(),
                        ),
                        onChanged: (v) => widget.viewModel.reviewText = v,
                      ),
                    ),
                    
                    // Photo upload section (only for products)
                    if (widget.isProduct) ...[
                      const SizedBox(height: 16),
                      
                      // Show already-uploaded URLs and newly picked images together
                      if ((_initialImageUrls.isNotEmpty ||
                          widget.viewModel.selectedImages.isNotEmpty))
                        Container(
                          height: 80,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              // Already-uploaded thumbnails
                              ..._initialImageUrls.map((url) => Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        url,
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )),
                              // Newly picked local files
                              ...widget.viewModel.selectedImages.map((file) =>
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            image: DecorationImage(
                                              image: FileImage(file),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () => setState(() => widget
                                                .viewModel.selectedImages
                                                .remove(file)),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.close,
                                                  color: Colors.white, size: 14),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      
                      // Add image button
                      if ((_initialImageUrls.length +
                              widget.viewModel.selectedImages.length) < 3)
                        GestureDetector(
                          onTap: () async {
                            final img = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 70,
                            );
                            if (img != null) {
                              setState(() => widget.viewModel.selectedImages
                                  .add(File(img.path)));
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A86B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate,
                                    size: 18, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(widget.l10n.addImage,
                                    style: const TextStyle(
                                        fontSize: 14, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Bottom buttons
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: widget.isDarkMode
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
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          widget.l10n.cancel,
                          style: TextStyle(
                            fontSize: 16,
                            color: widget.isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        color: _submitting
                            ? CupertinoColors.inactiveGray
                            : const Color(0xFF00A86B),
                        onPressed: _submitting ? null : _handleSubmit,
                        child: Text(
                          widget.l10n.submit,
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
    )
  );
}
}
