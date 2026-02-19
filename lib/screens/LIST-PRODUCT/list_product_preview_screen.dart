import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../utils/firebase_data_cleaner.dart';

class ListProductPreviewScreen extends StatefulWidget {
  final Product product;
  final List<XFile> imageFiles;
  final XFile? videoFile;
  final String phone;
  final String region;
  final String address;
  final String ibanOwnerName;
  final String ibanOwnerSurname;
  final String iban;
  final bool isEditMode; // Add this
  final Product? originalProduct;
  final bool isFromArchivedCollection;

  const ListProductPreviewScreen({
    Key? key,
    required this.product,
    required this.imageFiles,
    this.videoFile,
    required this.phone,
    required this.region,
    required this.address,
    required this.ibanOwnerName,
    required this.ibanOwnerSurname,
    required this.iban,
    this.isEditMode = false, // Add this
    this.originalProduct,
    this.isFromArchivedCollection = false,
  }) : super(key: key);

  @override
  _ListProductPreviewScreenState createState() =>
      _ListProductPreviewScreenState();
}

class _ListProductPreviewScreenState extends State<ListProductPreviewScreen> {
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Localize category and subcategory
    String localizedCategory =
        AllInOneCategoryData.localizeCategoryKey(widget.product.category, l10n);
    String localizedSubcategory = AllInOneCategoryData.localizeSubcategoryKey(
        widget.product.category, widget.product.subcategory, l10n);

    String? localizedSubSubcategory;
    if (widget.product.subsubcategory.isNotEmpty) {
      localizedSubSubcategory = AllInOneCategoryData.localizeSubSubcategoryKey(
          widget.product.category,
          widget.product.subcategory,
          widget.product.subsubcategory,
          l10n);
    }

    // Get color names for display
    String? colorDisplay;
    if (widget.product.colorImages.isNotEmpty) {
      List<String> localizedColors =
          widget.product.colorImages.keys.map((colorName) {
        return AttributeLocalizationUtils.localizeColorName(colorName, l10n);
      }).toList();
      colorDisplay = localizedColors.join(', ');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditMode ? l10n.previewEditProduct : l10n.previewProduct,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
        iconTheme:
            IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Container(
              color: isDarkMode
                  ? const Color(0xFF1C1A29)
                  : const Color(0xFFF5F5F5),
              child: SafeArea(
                bottom: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Details Section
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.productDetails,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Display Images
                            if (widget.imageFiles.isNotEmpty ||
                                (widget.isEditMode &&
                                    widget.product.imageUrls.isNotEmpty))
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                children: [
                                  // Show existing images first (in edit mode)
                                  if (widget.isEditMode &&
                                      widget.product.imageUrls.isNotEmpty)
                                    ...widget.product.imageUrls.map((imageUrl) {
                                      return ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                        child: Image.network(
                                          imageUrl,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child,
                                              loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;
                                            return Container(
                                              width: 100,
                                              height: 100,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300],
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                              ),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                  value: loadingProgress
                                                              .expectedTotalBytes !=
                                                          null
                                                      ? loadingProgress
                                                              .cumulativeBytesLoaded /
                                                          loadingProgress
                                                              .expectedTotalBytes!
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Container(
                                              width: 100,
                                              height: 100,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300],
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                              ),
                                              child: Icon(
                                                Icons.error,
                                                color: Colors.red,
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    }).toList(),

                                  // Show new images (if any)
                                  ...widget.imageFiles.map((image) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(8.0),
                                      child: Image.file(
                                        File(image.path),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            const SizedBox(height: 16),
                            // Display Product Details
                            _buildDetailRow(
                              context: context,
                              title: l10n.productTitle,
                              value: widget.product.productName,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.category,
                              value: localizedCategory,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.subcategory,
                              value: localizedSubcategory,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.subSubcategory ??
                                  'Sub-subcategory', // Add this to your l10n if missing
                              value: localizedSubSubcategory ?? '',
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.brand,
                              value: widget.product.brandModel ?? '',
                            ),
                            if (colorDisplay != null)
                              _buildDetailRow(
                                context: context,
                                title: l10n.color,
                                value: colorDisplay,
                              ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.condition,
                              value: widget.product.condition,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.price,
                              value: '${widget.product.price}',
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.quantity,
                              value: widget.product.quantity.toString(),
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.description,
                              value: widget.product.description,
                            ),

                            // Display Dynamic Attributes
                            if (widget.product.attributes.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                l10n.details,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...widget.product.attributes.entries.map((entry) {
                                try {
                                  // Use the utility to get localized title and value
                                  String localizedTitle =
                                      AttributeLocalizationUtils
                                          .getLocalizedAttributeTitle(
                                              entry.key, l10n);
                                  String localizedValue =
                                      AttributeLocalizationUtils
                                          .getLocalizedAttributeValue(
                                              entry.key, entry.value, l10n);

                                  // Only display if value is not empty
                                  if (localizedValue.isNotEmpty) {
                                    return _buildDetailRow(
                                      context: context,
                                      title: localizedTitle,
                                      value: localizedValue,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                } catch (e) {
                                  // Fallback to original logic
                                  String displayValue = '';
                                  if (entry.value is List) {
                                    displayValue =
                                        (entry.value as List).join(', ');
                                  } else {
                                    displayValue = entry.value.toString();
                                  }

                                  if (displayValue.isNotEmpty) {
                                    return _buildDetailRow(
                                      context: context,
                                      title: entry.key,
                                      value: displayValue,
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }
                              }).toList(),
                            ],

                            // Display Video if it exists
                            if (widget.videoFile != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  Text(
                                    l10n.video,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  VideoPlayerWidget(
                                      file: File(widget.videoFile!.path)),
                                ],
                              ),
                            // Display Color Images if any
                            if (widget.product.colorImages.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                l10n.colorImages,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: widget.product.colorImages.entries
                                    .map((entry) {
                                  // Get localized color name
                                  String localizedColorName =
                                      AttributeLocalizationUtils
                                          .localizeColorName(entry.key, l10n);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          localizedColorName, // Use localized color name
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8.0,
                                          runSpacing: 8.0,
                                          children: entry.value.map((url) {
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                              child: Image.network(
                                                url,
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Seller Information Section
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.sellerInformation,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              context: context,
                              title: l10n.name,
                              value: widget.product.sellerName,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.phoneNumber,
                              value: widget.phone,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.region,
                              value: widget.region,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.addressDetails,
                              value: widget.address,
                            ),
                            _buildDetailRow(
                              context: context,
                              title: l10n.bankAccountNumberIban,
                              value: widget.iban,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Delivery Option Section
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.deliveryOption,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.asset(
                                    widget.product.deliveryOption ==
                                            'Self Delivery'
                                        ? 'assets/images/selfdelivery.png'
                                        : 'assets/images/fastdelivery.png',
                                    width: 70,
                                    height: 70,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    widget.product.deliveryOption ==
                                            'Self Delivery'
                                        ? l10n.selfDelivery
                                        : l10n.fastDelivery,
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.product.deliveryOption == 'Self Delivery'
                                  ? l10n.selfDeliveryDescription
                                  : l10n.fastDeliveryDescription,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? Colors.grey[700]
                                    : Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Stock Information Section
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.stockInformation,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        color: isDarkMode
                            ? const Color.fromARGB(255, 33, 31, 49)
                            : Colors.white,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Image.asset(
                                  'assets/images/caution.png',
                                  width: 40,
                                  height: 40,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    l10n.stockInformation,
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.stockInformationDescription,
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? Colors.grey[700]
                                    : Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Confirm and Edit Buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  context.pop();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00A86B),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 16.0),
                                ),
                                child: Text(
                                  l10n.edit,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _submitProduct,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00A86B),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 16.0),
                                ),
                                child: Text(
                                  widget.isEditMode
                                      ? l10n.submitEdit
                                      : l10n.confirmAndList,
                                  style: const TextStyle(fontSize: 14),
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
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.secondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required BuildContext context,
    required String title,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$title:',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.grey[800]
                    : Colors.grey[300],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this method after _buildDetailRow and before _submitProduct
  Map<String, dynamic> _detectChanges(Product original, Product updated) {
    final List<String> editedFields = [];
    final Map<String, dynamic> changes = {};

    // Helper to normalize empty values for comparison
    dynamic normalizeValue(dynamic val) {
      if (val == null ||
          val == '' ||
          (val is List && val.isEmpty) ||
          (val is Map && val.isEmpty)) {
        return null;
      }
      return val;
    }

    // Helper to compare values
    void compareField(String fieldName, dynamic oldValue, dynamic newValue) {
      final normalizedOld = normalizeValue(oldValue);
      final normalizedNew = normalizeValue(newValue);

      if (jsonEncode(normalizedOld) != jsonEncode(normalizedNew)) {
        editedFields.add(fieldName);
        changes[fieldName] = {
          'old': oldValue,
          'new': newValue,
        };
      }
    }

    // Compare each field
    compareField('productName', original.productName, updated.productName);
    compareField('description', original.description, updated.description);
    compareField('price', original.price, updated.price);
    compareField('condition', original.condition, updated.condition);
    compareField('brandModel', original.brandModel, updated.brandModel);
    compareField('category', original.category, updated.category);
    compareField('subcategory', original.subcategory, updated.subcategory);
    compareField(
        'subsubcategory', original.subsubcategory, updated.subsubcategory);
    compareField('gender', original.gender, updated.gender);
    compareField('quantity', original.quantity, updated.quantity);
    compareField(
        'deliveryOption', original.deliveryOption, updated.deliveryOption);
    compareField('imageUrls', original.imageUrls, updated.imageUrls);
    compareField('videoUrl', original.videoUrl, updated.videoUrl);
    compareField('colorImages', original.colorImages, updated.colorImages);
    compareField(
        'colorQuantities', original.colorQuantities, updated.colorQuantities);
    compareField('attributes', original.attributes, updated.attributes);

    return {
      'editedFields': editedFields,
      'changes': changes,
    };
  }

  Future<void> _submitProduct() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _isLoading = true;
    });

    try {
      User? user = _auth.currentUser;
      if (user == null) {
        if (mounted) context.push('/login');
        return;
      }

      // Handle images properly - DON'T duplicate existing ones
      List<String> imageUrls = [];

      // In edit mode, start with existing images (DON'T upload them again)
      if (widget.isEditMode && widget.product.imageUrls.isNotEmpty) {
        imageUrls.addAll(widget.product.imageUrls);
      }

      // ONLY upload NEW images (not existing ones)
      if (widget.imageFiles.isNotEmpty) {
        List<String> newImageUrls = await _uploadFiles(
          widget.imageFiles.map((xfile) => File(xfile.path)).toList(),
          'default_images',
        );
        imageUrls.addAll(newImageUrls);
      }

      // Handle video
      String? videoUrl;
      if (widget.isEditMode && widget.originalProduct?.videoUrl != null) {
        videoUrl = widget.originalProduct!.videoUrl;
      }

      if (widget.videoFile != null) {
        List<String> videoUrls = await _uploadFiles(
          [File(widget.videoFile!.path)],
          'preview_videos',
        );
        if (videoUrls.isNotEmpty) {
          videoUrl = videoUrls[0];
        }
      }

      // ✅ FIXED: Handle color images and quantities properly
      Map<String, List<String>> colorImages = {};
      Map<String, int> colorQuantities = {};
      List<String> availableColors = [];
      List<String> deletedColors = [];

      if (widget.isEditMode && widget.originalProduct != null) {
        // ✅ START WITH CURRENT (not original)
        if (widget.product.colorImages.isNotEmpty) {
          colorImages.addAll(widget.product.colorImages);
        }
        if (widget.product.colorQuantities.isNotEmpty) {
          colorQuantities.addAll(widget.product.colorQuantities);
        }

        // ✅ THEN detect deletions by comparing
        final originalColors = widget.originalProduct!.colorImages.keys.toSet();
        final currentColors = colorImages.keys.toSet();
        deletedColors = originalColors.difference(currentColors).toList();
      } else {
        // ✅ NEW PRODUCT MODE: Just use current colors
        if (widget.product.colorImages.isNotEmpty) {
          colorImages.addAll(widget.product.colorImages);
        }
        if (widget.product.colorQuantities.isNotEmpty) {
          colorQuantities.addAll(widget.product.colorQuantities);
        }
      }

      // ✅ Build availableColors from FINAL color data
      Set<String> allColors = {};
      allColors.addAll(colorImages.keys);
      allColors.addAll(colorQuantities.keys);
      availableColors = allColors.toList();

      final uuid = Uuid();
      final productId =
          widget.isEditMode ? widget.originalProduct!.id : uuid.v4();

      Product product = Product(
        id: productId,
        ownerId: widget.product.shopId ?? user.uid,
        productName: widget.product.productName,
        description: widget.product.description,
        price: widget.product.price,
        condition: widget.product.condition,
        brandModel: widget.product.brandModel,
        currency: "TL",
        gender: widget.product.gender,
        boostClickCountAtStart: widget.product.boostClickCountAtStart,
        imageUrls: imageUrls,
        averageRating:
            widget.isEditMode ? widget.originalProduct!.averageRating : 0.0,
        reviewCount:
            widget.isEditMode ? widget.originalProduct!.reviewCount : 0,
        clickCount: widget.isEditMode ? widget.originalProduct!.clickCount : 0,
        favoritesCount:
            widget.isEditMode ? widget.originalProduct!.favoritesCount : 0,
        cartCount: widget.isEditMode ? widget.originalProduct!.cartCount : 0,
        purchaseCount:
            widget.isEditMode ? widget.originalProduct!.purchaseCount : 0,
        userId: user.uid,
        shopId: widget.product.shopId,
        ilanNo: productId,
        createdAt: widget.isEditMode
            ? widget.originalProduct!.createdAt
            : Timestamp.now(),
        sellerName: widget.product.sellerName,
        category: widget.product.category,
        subcategory: widget.product.subcategory,
        subsubcategory: widget.product.subsubcategory,
        quantity: widget.product.quantity,
        deliveryOption: widget.product.deliveryOption,
        isFeatured: widget.isEditMode
            ? widget.originalProduct!.isFeatured
            : widget.product.isFeatured,
        isBoosted:
            widget.isEditMode ? widget.originalProduct!.isBoosted : false,
        boostedImpressionCount: widget.isEditMode
            ? widget.originalProduct!.boostedImpressionCount
            : 0,
        boostImpressionCountAtStart: widget.isEditMode
            ? widget.originalProduct!.boostImpressionCountAtStart
            : 0,
        promotionScore:
            widget.isEditMode ? widget.originalProduct!.promotionScore : 0,
        paused: widget.isEditMode ? widget.originalProduct!.paused : false,
        boostStartTime:
            widget.isEditMode ? widget.originalProduct!.boostStartTime : null,
        boostEndTime:
            widget.isEditMode ? widget.originalProduct!.boostEndTime : null,
        lastClickDate:
            widget.isEditMode ? widget.originalProduct!.lastClickDate : null,
        clickCountAtStart:
            widget.isEditMode ? widget.originalProduct!.clickCountAtStart : 0,
        colorImages: colorImages,
        colorQuantities: colorQuantities,
        availableColors: availableColors,
        videoUrl: videoUrl,
        attributes: widget.product.attributes,
        relatedProductIds: widget.isEditMode
            ? (widget.originalProduct!.relatedProductIds ?? [])
            : [],
        relatedLastUpdated: widget.isEditMode
            ? (widget.originalProduct!.relatedLastUpdated ??
                Timestamp.fromDate(DateTime(1970, 1, 1)))
            : Timestamp.fromDate(DateTime(
                1970, 1, 1)), // Epoch date so Cloud Function processes it first
        relatedCount:
            widget.isEditMode ? (widget.originalProduct!.relatedCount ?? 0) : 0,
      );

      Map<String, dynamic> productData = product.toMap();
      productData['shopId'] = widget.product.shopId;
      productData['phone'] = widget.phone;
      productData['region'] = widget.region;
      productData['address'] = widget.address;
      productData['ibanOwnerName'] = widget.ibanOwnerName;
      productData['ibanOwnerSurname'] = widget.ibanOwnerSurname;
      productData['iban'] = widget.iban;
      productData['updatedAt'] = FieldValue.serverTimestamp();

      final attributes = productData['attributes'];
      if (attributes is Map<String, dynamic>) {
        // If clothingTypes array exists, remove legacy clothingType
        if (attributes.containsKey('clothingTypes')) {
          attributes.remove('clothingType');
        }
        // If pantFabricTypes array exists, remove legacy pantFabricType
        if (attributes.containsKey('pantFabricTypes')) {
          attributes.remove('pantFabricType');
        }
      }

      productData = FirebaseDataCleaner.cleanData(productData);

      if (widget.isEditMode) {
        final changeDetection =
            _detectChanges(widget.originalProduct!, product);
        final List<String> editedFields =
            changeDetection['editedFields'] as List<String>;
        final Map<String, dynamic> changes =
            changeDetection['changes'] as Map<String, dynamic>;

        // ✅ Include deleted colors in metadata
        if (deletedColors.isNotEmpty) {
          productData['deletedColors'] = deletedColors;

          if (!editedFields.contains('colorImages')) {
            editedFields.add('colorImages');
          }

          if (!changes.containsKey('colorImages')) {
            changes['colorImages'] = {
              'old': widget.originalProduct!.colorImages,
              'new': colorImages,
            };
          }
        }

        productData['originalProductId'] = widget.originalProduct!.id;
        productData['originalProductData'] = FirebaseDataCleaner.cleanData(
            widget.originalProduct?.toMap() ?? {});
        productData['submittedAt'] = FieldValue.serverTimestamp();
        productData['status'] = 'pending';
        productData['editedFields'] = editedFields;
        productData['changes'] = changes;

        // ✅ NEW: Handle archived product updates differently
        if (widget.isFromArchivedCollection) {
          productData['editType'] = 'archived_product_update';
          productData['sourceCollection'] = 'paused_shop_products';
          // Clear the archive flags in the submitted data (will be applied on approval)
          productData['needsUpdate'] = false;
          productData['archiveReason'] = null;
          productData['archivedByAdmin'] = false;
          productData['archivedByAdminAt'] = null;
          productData['archivedByAdminId'] = null;
          productData['paused'] = false; // Will be unpaused on approval
        } else {
          productData['editType'] = 'product_edit';
          productData['sourceCollection'] = 'shop_products';
        }

        final editCollection = widget.product.shopId == null
            ? 'vitrin_edit_product_applications'
            : 'product_edit_applications';

        final editApplicationId = uuid.v4();
        await _firestore
            .collection(editCollection)
            .doc(editApplicationId)
            .set(productData);
      } else {
        productData['status'] = 'pending';

        // Normal users go to vitrin_product_applications, shops go to product_applications
        final collection = widget.product.shopId == null
            ? 'vitrin_product_applications'
            : 'product_applications';

        await _firestore.collection(collection).doc(productId).set(productData);
      }
      if (!mounted) return;
      context.go('/success');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorListingProduct)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<String>> _uploadFiles(List<File> files, String folder) async {
    List<String> urls = [];
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return urls;
    String userId = user.uid;

    for (File file in files) {
      try {
        String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
        Reference ref = FirebaseStorage.instance
            .ref()
            .child('products/$userId/$folder/$fileName');
        UploadTask uploadTask = ref.putFile(file);
        TaskSnapshot snapshot = await uploadTask;
        String url = await snapshot.ref.getDownloadURL();
        urls.add(url);
      } catch (e) {
        continue;
      }
    }
    return urls;
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final File file;

  const VideoPlayerWidget({Key? key, required this.file}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
        _controller.setLooping(true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_controller),
                _ControlsOverlay(controller: _controller),
                VideoProgressIndicator(_controller, allowScrubbing: true),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({Key? key, required this.controller})
      : super(key: key);

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        controller.value.isPlaying ? controller.pause() : controller.play();
      },
      child: Stack(
        children: <Widget>[
          controller.value.isPlaying
              ? const SizedBox.shrink()
              : Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 60.0,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
