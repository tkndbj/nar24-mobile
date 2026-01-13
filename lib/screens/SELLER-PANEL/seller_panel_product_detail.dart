import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../../../providers/seller_panel_provider.dart';
import 'package:google_fonts/google_fonts.dart';

class SellerPanelProductDetail extends StatefulWidget {
  final Product product;

  const SellerPanelProductDetail({required this.product, Key? key})
      : super(key: key);

  @override
  State<SellerPanelProductDetail> createState() =>
      _SellerPanelProductDetailState();
}

class _SellerPanelProductDetailState extends State<SellerPanelProductDetail> {
  String? _selectedImageUrl;
  bool _imagesPrecached = false;
  // Controllers for sale preferences
  late TextEditingController _maxQuantityController;
  late TextEditingController _discountThresholdController;
  late TextEditingController _discountPercentageController;

  /// Real-time product listener subscription
  StreamSubscription<DocumentSnapshot>? _productSubscription;

  /// Live product data from Firestore listener
  Product? _liveProduct;

  // Viewer role state
  bool _isViewer = false;

  @override
  void initState() {
    super.initState();
    _maxQuantityController = TextEditingController();
    _discountThresholdController = TextEditingController();
    _discountPercentageController = TextEditingController();

    _setupProductListener();
    _checkUserRole();
    _loadSalePreferences();
  }

  /// Checks if the current user has only viewer role for the shop.
  Future<void> _checkUserRole() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final shopId = widget.product.shopId;
      if (shopId == null) return;

      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
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

  /// Sets up a real-time listener for the product document
  void _setupProductListener() {
    final productRef = widget.product.reference;
    if (productRef == null) return;

    _productSubscription = productRef.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        if (snapshot.exists) {
          setState(() {
            _liveProduct = Product.fromDocument(snapshot);
          });
        }
      },
      onError: (error) {
        debugPrint('Error listening to product updates: $error');
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only precache once
    if (!_imagesPrecached) {
      _imagesPrecached = true;

      for (String url in widget.product.imageUrls) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
      widget.product.colorImages.forEach((_, urls) {
        for (String url in urls) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      });
    }
  }

  @override
  void dispose() {
    _productSubscription?.cancel();
    _maxQuantityController.dispose();
    _discountThresholdController.dispose();
    _discountPercentageController.dispose();
    super.dispose();
  }

  // Get current product - prioritizes live data from Firestore listener
  Product get _currentProduct {
    // First priority: live product from real-time listener
    if (_liveProduct != null) {
      return _liveProduct!;
    }

    // Fallback to provider data
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    // Try to find updated product from provider's products list
    try {
      final updatedProduct = provider.filteredProducts
          .firstWhere((p) => p.id == widget.product.id);
      return updatedProduct;
    } catch (e) {
      // If not found in filtered products, check main products list
      try {
        final productFromMap = provider.productMap[widget.product.id];
        if (productFromMap != null) {
          return productFromMap;
        }
      } catch (e) {
        debugPrint('Product not found in provider map: $e');
      }

      // Fallback to original product
      return widget.product;
    }
  }

  Future<void> _loadSalePreferences() async {
    if (widget.product.reference != null) {
      try {
        final doc = await widget.product.reference!.get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          setState(() {
            _maxQuantityController.text =
                (data?['maxQuantity'] ?? '').toString();
            _discountThresholdController.text =
                (data?['discountThreshold'] ?? '').toString();
            // Use bulkDiscountPercentage for sale preference, separate from normal discountPercentage
            _discountPercentageController.text =
                (data?['bulkDiscountPercentage'] ?? '').toString();
          });
        }
      } catch (e) {
        debugPrint("Error loading sale preferences: $e");
      }
    }
  }

  Future<void> _saveSalePreferences() async {
    FocusScope.of(context).unfocus();

    // Parse inputs; only include non-empty and valid values
    final Map<String, dynamic> updateData = {};
    final List<String> fieldsToRemove = [];

    final maxQuantity = _maxQuantityController.text.isNotEmpty
        ? int.tryParse(_maxQuantityController.text)
        : null;

    final discountThreshold = _discountThresholdController.text.isNotEmpty
        ? int.tryParse(_discountThresholdController.text)
        : null;

    final saleDiscountPercentage = _discountPercentageController.text.isNotEmpty
        ? int.tryParse(_discountPercentageController.text)
        : null;

    // ✅ ADD: Validate bulk discount fields must co-exist
    final hasThreshold = discountThreshold != null && discountThreshold > 0;
    final hasPercentage =
        saleDiscountPercentage != null && saleDiscountPercentage > 0;

    if (hasThreshold != hasPercentage) {
      // One is set but not the other
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).bulkDiscountFieldsRequired ??
                'Both quantity threshold and discount percentage must be set together',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if product has discount applied - block ONLY buy X to get Y discount (not maxQuantity)
    final currentProduct = _currentProduct;
    if (currentProduct.discountPercentage != null &&
        currentProduct.discountPercentage! > 0 &&
        (discountThreshold != null && discountThreshold > 0 ||
            saleDiscountPercentage != null && saleDiscountPercentage > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).cannotSetSalePreferenceWithDiscount ??
                'Cannot set sale preference with discount',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Track which fields should be set vs deleted
    if (maxQuantity != null && maxQuantity > 0) {
      updateData['maxQuantity'] = maxQuantity;
    } else {
      fieldsToRemove.add('maxQuantity');
    }

    if (discountThreshold != null && discountThreshold > 0) {
      updateData['discountThreshold'] = discountThreshold;
    } else {
      fieldsToRemove.add('discountThreshold');
    }

    // Use bulkDiscountPercentage field for sale preference (separate from normal discountPercentage)
    if (saleDiscountPercentage != null && saleDiscountPercentage > 0) {
      updateData['bulkDiscountPercentage'] = saleDiscountPercentage;
    } else {
      fieldsToRemove.add('bulkDiscountPercentage');
    }

    // Validate: discountThreshold must not exceed maxQuantity if both are provided
    if (updateData.containsKey('maxQuantity') &&
        updateData.containsKey('discountThreshold')) {
      if (updateData['discountThreshold'] > updateData['maxQuantity']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context).discountThresholdExceedsMax)),
        );
        return;
      }
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Update fields that have values
      if (updateData.isNotEmpty) {
        batch.update(widget.product.reference!, updateData);
      }

      // Remove fields that should be deleted
      if (fieldsToRemove.isNotEmpty) {
        final deleteData = <String, dynamic>{};
        for (final field in fieldsToRemove) {
          deleteData[field] = FieldValue.delete();
        }
        batch.update(widget.product.reference!, deleteData);
      }

      await batch.commit();

      // Success message
      final bool isDeleting = updateData.isEmpty && fieldsToRemove.isNotEmpty;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(isDeleting
                    ? (AppLocalizations.of(context).salePreferencesDeleted ??
                        'Sale preferences removed successfully')
                    : AppLocalizations.of(context)
                        .salePreferencesSavedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error managing sale preferences: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).errorSavingPreferences)),
        );
      }
    }
  }

  // ✅ GOOD - Apply dialogContext pattern
  Future<void> _applyIndividualDiscount(int percentage) async {
    final l10n = AppLocalizations.of(context);

    // Check if product has bulk discount sale preference - block normal discount
    final currentProduct = _currentProduct;
    if (currentProduct.bulkDiscountPercentage != null &&
        currentProduct.bulkDiscountPercentage! > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.cannotApplyDiscountWithSalePreference ??
                'Cannot apply discount when product has sale preference',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
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
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade400,
                                Colors.green.shade600
                              ],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.local_offer_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.applyingDiscount ?? 'Applying discount...',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 8,
                      width: double.infinity,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.green.shade400),
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
      },
    );

    try {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      final currentProduct = _currentProduct;
      final double basePrice =
          currentProduct.originalPrice ?? currentProduct.price;
      final double newPrice =
          double.parse((basePrice * (1 - percentage / 100)).toStringAsFixed(2));

      await widget.product.reference!.update({
        'originalPrice': basePrice,
        'discountPercentage': percentage,
        'price': newPrice,
      });

      final updatedProduct = currentProduct.copyWith(
        price: newPrice,
        originalPrice: basePrice,
        discountPercentage: percentage,
      );

      provider.updateProduct(widget.product.id, updatedProduct);

      // ✅ Close modal safely
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(l10n.discountApplied),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying discount: $e')),
        );
      }
    }
  }

  Future<void> _removeIndividualDiscount() async {
    final l10n = AppLocalizations.of(context);

    // Use live product data from listener (no need to fetch again)
    final product = _currentProduct;

    // Check if product is in a campaign using live data
    final campaignId = product.campaign;
    final campaignName = product.campaignName;

    if (campaignId != null && campaignId.isNotEmpty && campaignName != null) {
      showCupertinoModalPopup(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: Text(
            l10n.removeFromCampaignTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          message: Text(
            l10n.productInCampaignMessage(campaignName),
            style: const TextStyle(
                fontSize: 14, color: CupertinoColors.secondaryLabel),
          ),
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _processRemoveFromCampaignAndDiscount();
              },
              isDestructiveAction: true,
              child: Text(
                l10n.removeFromCampaignAndDiscount,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      );
      return;
    }

    // If not in campaign, proceed with normal discount removal
    await _processRemoveDiscountOnly();
  }

  Future<void> _processRemoveDiscountOnly() async {
    final l10n = AppLocalizations.of(context);

    // ✅ Show animated loading modal
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
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
                            gradient: LinearGradient(
                              colors: [
                                Colors.red.shade400,
                                Colors.red.shade600
                              ],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.local_offer_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.removingDiscount ?? 'Removing discount...',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 8,
                      width: double.infinity,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.red.shade400),
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
      },
    );

    try {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      final currentProduct = _currentProduct;
      final double basePrice =
          currentProduct.originalPrice ?? currentProduct.price;
      final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

      await widget.product.reference!.update({
        'price': cleanPrice,
        'discountPercentage': null,
        'originalPrice': null,
      });

      final updatedProduct = currentProduct.copyWith(
        price: cleanPrice,
        setOriginalPriceNull: true,
        setDiscountPercentageNull: true,
      );

      provider.updateProduct(widget.product.id, updatedProduct);

      // ✅ Close loading modal
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // ✅ Trigger rebuild
      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(l10n.discountRemoved),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing discount: $e')),
        );
      }
    }
  }

  Future<void> _processRemoveFromCampaignAndDiscount() async {
    final l10n = AppLocalizations.of(context);

    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
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
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.shade400,
                                Colors.deepOrange.shade600
                              ],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.removingFromCampaign ?? 'Removing from campaign...',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 8,
                      width: double.infinity,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.orange.shade400),
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
      },
    );

    try {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      final currentProduct = _currentProduct;
      final double basePrice =
          currentProduct.originalPrice ?? currentProduct.price;
      final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

      await widget.product.reference!.update({
        'price': cleanPrice,
        'discountPercentage': null,
        'originalPrice': null,
        'campaign': null,
        'campaignName': null,
      });

      final updatedProduct = currentProduct.copyWith(
        price: cleanPrice,
        setOriginalPriceNull: true,
        setDiscountPercentageNull: true,
        campaign: null,
        campaignName: null,
      );

      provider.updateProduct(widget.product.id, updatedProduct);

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(l10n.removedFromCampaignAndDiscount),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing from campaign: $e')),
        );
      }
    }
  }

  void _showSalePreferenceBlockDialog() {
    final l10n = AppLocalizations.of(context);

    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(l10n.cannotApplyDiscount ?? 'Cannot Apply Discount'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              l10n.cannotApplyDiscountWithSalePreference ??
                  'You need to remove the sale preference (buy X to get Y% discount) on this product first to apply normal discount',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: Text(l10n.ok ?? 'OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showDiscountModal() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Add listener to update validation
          controller.addListener(() {
            setState(() {});
          });

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: AnimatedPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height *
                        0.5, // Reduced from 0.6
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode
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
                              color: isDarkMode
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
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade400,
                                    Colors.red.shade600
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.local_offer_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.enterDiscountPercentage,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : Colors.black,
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
                            children: [
                              // Helper text
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        l10n.discountHelperText ??
                                            'Enter a discount percentage between 1% and 100%',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Discount input field
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _isValidDiscount(controller.text)
                                        ? Colors.green
                                        : (isDarkMode
                                            ? Colors.grey[600]!
                                            : Colors.grey[300]!),
                                    width: _isValidDiscount(controller.text)
                                        ? 2
                                        : 1,
                                  ),
                                  color: isDarkMode
                                      ? const Color.fromARGB(255, 45, 43, 61)
                                      : Colors.grey.shade50,
                                ),
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Icon(
                                        Icons.percent,
                                        color: isDarkMode
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        size: 20,
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.white
                                              : Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              l10n.discountRangePlaceholder,
                                          hintStyle: TextStyle(
                                            color: isDarkMode
                                                ? Colors.grey[500]
                                                : Colors.grey[500],
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: Text(
                                        '%',
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Validation message
                              if (controller.text.isNotEmpty &&
                                  !_isValidDiscount(controller.text))
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          l10n.invalidDiscountRange,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              // Success message
                              if (_isValidDiscount(controller.text))
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          l10n.validDiscountMessage ??
                                              'Valid discount percentage',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green,
                                            fontWeight: FontWeight.w500,
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

                      // Bottom buttons
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: isDarkMode
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
                                  l10n.cancel,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CupertinoButton(
                                color: _isValidDiscount(controller.text)
                                    ? const Color(0xFF007AFF)
                                    : CupertinoColors.inactiveGray,
                                onPressed: _isValidDiscount(controller.text)
                                    ? () async {
                                        final input =
                                            int.parse(controller.text);
                                        Navigator.pop(
                                            context); // Close modal first
                                        await _applyIndividualDiscount(input);
                                      }
                                    : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.confirm,
                                      style: TextStyle(
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

// Helper method to validate discount input
  bool _isValidDiscount(String input) {
    final value = int.tryParse(input);
    return value != null && value >= 1 && value <= 100;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final imageUrls = widget.product.imageUrls;
    final colorImages = widget.product.colorImages;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Wrap the entire widget in Consumer to listen to provider changes
    return Consumer<SellerPanelProvider>(
      builder: (context, provider, child) {
        final currentProduct = _currentProduct;

        return Scaffold(
          backgroundColor: isDarkMode
              ? const Color(0xFF1C1A29)
              : const Color.fromARGB(255, 235, 235, 235),
          body: SafeArea(
            top: false,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: _selectedImageUrl != null
                  ? _buildFullScreenImage()
                  : _buildProductDetails(
                      imageUrls, colorImages, isDarkMode, currentProduct),
            ),
          ),
        );
      },
    );
  }

  void _showLoadingModal(BuildContext context, String message,
      {IconData? icon, List<Color>? gradientColors}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
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
                            gradient: LinearGradient(
                              colors: gradientColors ??
                                  [Colors.blue, Colors.blueAccent],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Icon(
                            icon ?? Icons.sync_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 8,
                      width: double.infinity,
                      color: isDarkMode
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              gradientColors?.first ?? Colors.blue,
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
      },
    );
  }

  Widget _buildFullScreenImage() {
    return Stack(
      children: [
        Container(
          color: Colors.black,
          child: CachedNetworkImage(
            imageUrl: _selectedImageUrl!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.error_outline, color: Colors.white, size: 48),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(25),
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 24),
              onPressed: () {
                setState(() {
                  _selectedImageUrl = null;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  String formatPrice(num price) {
    double rounded = double.parse(price.toStringAsFixed(2));

    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }

    return rounded.toStringAsFixed(2);
  }

  Widget _buildProductDetails(
      List<String> imageUrls,
      Map<String, List<String>> colorImages,
      bool isDarkMode,
      Product currentProduct) {
    final l10n = AppLocalizations.of(context);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Custom App Bar
        SliverAppBar(
          expandedHeight: 0,
          floating: true,
          pinned: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Container(
            margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color:
                  isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          actions: [
            // Discount Button - hidden for viewers
            if (!_isViewer)
              Container(
                margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: currentProduct.discountPercentage != null
                      ? LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        )
                      : LinearGradient(
                          colors: [Colors.green.shade400, Colors.green.shade600],
                        ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      // Check if product has sale preference (buy X to get Y% discount)
                      final hasSalePreference =
                          currentProduct.discountThreshold != null &&
                              currentProduct.bulkDiscountPercentage != null &&
                              currentProduct.discountThreshold! > 0 &&
                              currentProduct.bulkDiscountPercentage! > 0;

                      if (currentProduct.discountPercentage != null) {
                        _removeIndividualDiscount();
                      } else if (hasSalePreference) {
                        // Show alert dialog when sale preference exists
                        _showSalePreferenceBlockDialog();
                      } else {
                        _showDiscountModal();
                      }
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        currentProduct.discountPercentage != null
                            ? l10n.removeDiscount
                            : l10n.applyDiscount,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Edit Button - hidden for viewers
            if (!_isViewer)
              Container(
                margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color:
                      isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                  onPressed: () {
                    // Check if product has restrictions that prevent editing
                    final isInBundle = currentProduct.bundleIds.isNotEmpty;
                    final isInCampaign = currentProduct.campaign != null &&
                        currentProduct.campaign!.isNotEmpty;
                    final hasSalePreference =
                        currentProduct.discountThreshold != null &&
                            currentProduct.discountThreshold! > 0 &&
                            currentProduct.bulkDiscountPercentage != null &&
                            currentProduct.bulkDiscountPercentage! > 0;

                    if (isInBundle || isInCampaign || hasSalePreference) {
                      showCupertinoDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return CupertinoAlertDialog(
                            title: Text(l10n.cannotEditProduct),
                            content: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(l10n.cannotEditProductMessage),
                            ),
                            actions: [
                              CupertinoDialogAction(
                                child: Text(l10n.ok ?? 'OK'),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          );
                        },
                      );
                      return;
                    }

                    context.push('/edit-product-shop', extra: {
                      'product': widget.product,
                      'shopId': widget.product.shopId,
                    });
                  },
                ),
              ),
          ],
        ),

        // Product Content
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 8),

              // Product Header Card - Pass currentProduct
              _buildProductHeaderCard(isDarkMode, currentProduct),

              // Product Gallery
              if (imageUrls.isNotEmpty)
                _buildProductGallery(imageUrls, isDarkMode),

              // Product Stats
              _buildProductStats(isDarkMode),

              // Color Variants
              if (colorImages.isNotEmpty)
                _buildColorVariants(colorImages, isDarkMode),

              // Sale Preferences - hidden for viewers
              if (!_isViewer)
                _buildSalePreferences(isDarkMode),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  // Update this method to accept currentProduct parameter
  Widget _buildProductHeaderCard(bool isDarkMode, Product currentProduct) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Product Name and Status
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.productName.isNotEmpty
                          ? widget.product.productName
                          : l10n.unnamedProduct,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // ─── Firestore ID + copy button ─────────────────────
                    Row(
                      children: [
                        Text(
                          'ID: ${widget.product.reference?.id ?? widget.product.id}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(
                                text: widget.product.reference?.id ??
                                    widget.product.id));
                            // show floating success snackbar with icon
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(l10n.productIdCopied),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Icon(
                            Icons.copy,
                            size: 14,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.productDetails,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Use currentProduct for discount display
              if (currentProduct.discountPercentage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade600],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${currentProduct.discountPercentage}% ${l10n.off}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Price Section - Use currentProduct
          Row(
            children: [
              Icon(
                Icons.monetization_on_outlined,
                size: 18,
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.currentPrice,
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${formatPrice(currentProduct.price)} ${widget.product.currency}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Keep all the other build methods unchanged...
  // (The rest of the methods remain the same as in your original code)

  Widget _buildProductGallery(List<String> imageUrls, bool isDarkMode) {
    // ... existing implementation
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  size: 16,
                  color: Colors.blue.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.productGallery,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${imageUrls.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 75,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedImageUrl = imageUrls[index];
                      });
                    },
                    child: Hero(
                      tag: 'product_image_$index',
                      child: Container(
                        width: 75,
                        height: 75,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: imageUrls[index],
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey.shade200,
                                    Colors.grey.shade100,
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blue),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 24,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductStats(bool isDarkMode) {
    final l10n = AppLocalizations.of(context);
    final stats = [
      {
        'label': l10n.quantity,
        'value': widget.product.quantity.toString(),
        'icon': Icons.inventory_2_outlined,
        'color': Colors.blue,
      },
      {
        'label': l10n.averageRating,
        'value': widget.product.averageRating.toStringAsFixed(1),
        'icon': Icons.star_outline,
        'color': Colors.amber,
      },
      {
        'label': l10n.views,
        'value': widget.product.clickCount.toString(),
        'icon': Icons.visibility_outlined,
        'color': Colors.purple,
      },
      {
        'label': l10n.cartCount,
        'value': widget.product.cartCount.toString(),
        'icon': Icons.shopping_cart_outlined,
        'color': Colors.orange,
      },
      {
        'label': l10n.purchases,
        'value': widget.product.purchaseCount.toString(),
        'icon': Icons.shopping_bag_outlined,
        'color': Colors.red,
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  size: 16,
                  color: Colors.green.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.productAnalytics,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats in a more mobile-friendly layout
          ...stats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            final color = stat['color'] as Color;

            return Container(
              margin:
                  EdgeInsets.only(bottom: index == stats.length - 1 ? 0 : 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      stat['icon'] as IconData,
                      size: 16,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      stat['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      stat['value'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildColorVariants(
      Map<String, List<String>> colorImages, bool isDarkMode) {
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  size: 16,
                  color: Colors.purple.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.colorVariants,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${colorImages.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...colorImages.entries.map((entry) {
            final colorName = entry.key;
            final imageUrl = entry.value.isNotEmpty ? entry.value[0] : '';
            final quantity = (widget.product.colorQuantities[colorName] ?? 0);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Color Image
                  if (imageUrl.isNotEmpty)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade200,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),

                  // Color Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          colorName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.availableInStock,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Quantity Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade50, Colors.blue.shade100],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$quantity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSalePreferences(bool isDarkMode) {
    final l10n = AppLocalizations.of(context);
    final currentProduct = _currentProduct;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tune_outlined,
                  size: 16,
                  color: Colors.indigo.shade600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.salePreferences,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Max Quantity Section (always enabled)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.grey[800]! : Colors.grey[200]!,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.cyan.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.inventory_outlined,
                        size: 14,
                        color: Colors.cyan.shade600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.maximumQuantityLimit,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Max Quantity Input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.salePreferenceMaxQuantityPre,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 40,
                            child: TextField(
                              controller: _maxQuantityController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.cyan.shade700,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                      color: Colors.cyan.shade400, width: 2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade300),
                                ),
                                filled: true,
                                fillColor: isDarkMode
                                    ? Colors.grey[800]
                                    : Colors.white,
                                hintText: '0',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: Text(
                            l10n.salePreferenceMaxQuantityPost,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Bulk Discount Section
          // Check if product has normal discount, is in bundle, or in campaign
          Builder(
            builder: (context) {
              final hasNormalDiscount =
                  currentProduct.discountPercentage != null &&
                      currentProduct.discountPercentage! > 0;
              final isInBundle = currentProduct.bundleIds.isNotEmpty;
              final isInCampaign = currentProduct.campaign != null &&
                  currentProduct.campaign!.isNotEmpty;
              final isDisabled =
                  hasNormalDiscount || isInBundle || isInCampaign;

              return Column(
                children: [
                  Opacity(
                    opacity: isDisabled ? 0.5 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF8FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[800]!
                              : Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.local_offer_outlined,
                                  size: 14,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l10n.bulkPurchaseDiscount,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Discount Threshold Input
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.salePreferenceDiscountPre,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      height: 40,
                                      child: TextField(
                                        controller:
                                            _discountThresholdController,
                                        enabled: !isDisabled,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade700,
                                        ),
                                        decoration: InputDecoration(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.orange.shade400,
                                                width: 2),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          filled: true,
                                          fillColor: isDarkMode
                                              ? Colors.grey[800]
                                              : Colors.white,
                                          hintText: '0',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      l10n.salePreferenceDiscountMid,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Discount Percentage Input
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.applyDiscountOf,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      height: 40,
                                      child: TextField(
                                        controller:
                                            _discountPercentageController,
                                        enabled: !isDisabled,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.red.shade700,
                                        ),
                                        decoration: InputDecoration(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.red.shade400,
                                                width: 2),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          filled: true,
                                          fillColor: isDarkMode
                                              ? Colors.grey[800]
                                              : Colors.white,
                                          hintText: '0',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      l10n.salePreferenceDiscountPost,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Warning message if product is in bundle or campaign
                  if (isInBundle || isInCampaign) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isInBundle
                                  ? l10n.cannotSetSalePreferenceInBundle
                                  : l10n.cannotSetSalePreferenceInCampaign,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade800,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Save Button - Disable if discount is active or in bundle/campaign
          Builder(builder: (context) {
            final hasNormalDiscount =
                currentProduct.discountPercentage != null &&
                    currentProduct.discountPercentage! > 0;
            final isInBundle = currentProduct.bundleIds.isNotEmpty;
            final isInCampaign = currentProduct.campaign != null &&
                currentProduct.campaign!.isNotEmpty;
            final isDisabled = hasNormalDiscount || isInBundle || isInCampaign;

            return Opacity(
              opacity: isDisabled ? 0.5 : 1.0,
              child: Container(
                width: double.infinity,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade500, Colors.blue.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isDisabled
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            _saveSalePreferences();
                          },
                    child: Container(
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.save_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.savePreferencesButtonLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
        ],
      ),
    );
  }
}
