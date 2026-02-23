import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import 'seller_panel_campaign_success_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SellerPanelCampaignDiscountScreen extends StatefulWidget {
  final Map<String, dynamic> campaign;
  final List<Product> selectedProducts;
  final String shopId;

  const SellerPanelCampaignDiscountScreen({
    super.key,
    required this.campaign,
    required this.selectedProducts,
    required this.shopId,
  });

  @override
  State<SellerPanelCampaignDiscountScreen> createState() =>
      _SellerPanelCampaignDiscountScreenState();
}

class _SellerPanelCampaignDiscountScreenState
    extends State<SellerPanelCampaignDiscountScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _bulkDiscountController = TextEditingController();
  final Map<String, TextEditingController> _individualControllers = {};
  final Map<String, double> _productDiscounts = {};
  final Map<String, FocusNode> _focusNodes = {};

  /// Deduplicated list of products (ensures no duplicates by product ID)
  late List<Product> _uniqueProducts;

  // ✅ CHANGE: Replaced full collection listener with targeted per-document
  // listeners ONLY for blocked products (sale preference / bundle).
  // Unblocked products don't need real-time updates on this screen.
  final Map<String, StreamSubscription<DocumentSnapshot>>
      _blockedProductListeners = {};

  late AnimationController _fabAnimationController;
  late AnimationController _bulkAnimationController;
  late Animation<double> _fabScaleAnimation;
  late Animation<Offset> _fabSlideAnimation;
  late Animation<double> _bulkScaleAnimation;

  bool _isApplyingBulk = false;
  bool _isSaving = false;
  bool _showBulkInput = false;
  String? _errorMessage;

  static const double _minDiscountPercentage = 5.0;
  static const double _maxDiscountPercentage = 90.0;

  // Modern color scheme
  static const Color _primaryColor = Color(0xFF6366F1); // Indigo
  static const Color _surfaceColor = Color(0xFFFAFAFC);
  static const Color _cardColor = Colors.white;
  static const Color _successColor = Color(0xFF10B981); // Emerald
  static const Color _errorColor = Color(0xFFEF4444); // Red
  static const Color _warningColor = Color(0xFFF59E0B); // Amber
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _darkBackground = Color(0xFF1C1A29);
  static const Color _darkCard = Color(0xFF211F31);

  @override
  void initState() {
    super.initState();
    _deduplicateProducts();
    _initializeAnimations();
    _initializeControllers();
    _attachBlockedProductListeners(); // ✅ CHANGE: targeted listeners only
  }

  /// Removes duplicate products by keeping only the first occurrence of each product ID
  void _deduplicateProducts() {
    final seenIds = <String>{};
    _uniqueProducts = widget.selectedProducts.where((product) {
      if (seenIds.contains(product.id)) {
        return false;
      }
      seenIds.add(product.id);
      return true;
    }).toList();
  }

  // ✅ CHANGE: Replaced _setupProductsListener with targeted listeners.
  // Only listens to individual documents that are blocked (sale preference
  // or bundle). When a blocked product becomes unblocked (e.g. user removed
  // sale preference), its listener self-cancels. If zero products are blocked,
  // zero listeners are created — completely free.
  void _attachBlockedProductListeners() {
    for (final product in _uniqueProducts) {
      if (!_isProductBlocked(product)) continue;

      // Skip if already listening
      if (_blockedProductListeners.containsKey(product.id)) continue;

      _blockedProductListeners[product.id] = _firestore
          .collection('shop_products')
          .doc(product.id)
          .snapshots()
          .listen(
        (docSnapshot) {
          if (!mounted || !docSnapshot.exists) return;

          final updatedProduct = Product.fromDocument(docSnapshot);
          final stillBlocked = _isProductBlocked(updatedProduct);

          setState(() {
            final index = _uniqueProducts.indexWhere((p) => p.id == product.id);
            if (index != -1) {
              _uniqueProducts[index] = updatedProduct;
            }
          });

          // Self-cancel when no longer blocked — listener served its purpose
          if (!stillBlocked) {
            _blockedProductListeners[product.id]?.cancel();
            _blockedProductListeners.remove(product.id);
          }
        },
        onError: (e) {
          debugPrint('Error listening to blocked product ${product.id}: $e');
          _blockedProductListeners[product.id]?.cancel();
          _blockedProductListeners.remove(product.id);
        },
      );
    }
  }

  /// Returns true if product cannot receive a campaign discount.
  bool _isProductBlocked(Product product) {
    final hasSalePreference = product.discountThreshold != null &&
        product.bulkDiscountPercentage != null &&
        product.discountThreshold! > 0 &&
        product.bulkDiscountPercentage! > 0;
    final isInBundle = product.bundleIds.isNotEmpty;
    return hasSalePreference || isInBundle;
  }

  void _cancelBlockedListeners() {
    for (final sub in _blockedProductListeners.values) {
      sub.cancel();
    }
    _blockedProductListeners.clear();
  }

  void _initializeAnimations() {
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _bulkAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fabScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.elasticOut,
    ));

    _fabSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeOutBack,
    ));

    _bulkScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bulkAnimationController,
      curve: Curves.elasticOut,
    ));

    // Trigger FAB animation immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fabAnimationController.forward();
    });
  }

  void _initializeControllers() {
    // Initialize only the discount map, not controllers/focus nodes
    for (final product in _uniqueProducts) {
      _productDiscounts[product.id] = 0.0;
    }
  }

  // Lazy controller/focus node getters
  TextEditingController _getController(String productId) {
    return _individualControllers.putIfAbsent(
      productId,
      () => TextEditingController(),
    );
  }

  FocusNode _getFocusNode(String productId) {
    return _focusNodes.putIfAbsent(
      productId,
      () => FocusNode(),
    );
  }

  @override
  void dispose() {
    _cancelBlockedListeners(); // ✅ CHANGE: cancel targeted listeners
    _fabAnimationController.dispose();
    _bulkAnimationController.dispose();
    _bulkDiscountController.dispose();

    for (final controller in _individualControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }

    super.dispose();
  }

  bool _validateDiscountPercentage(String value, Product product) {
    // If field is empty, check if existing discount is valid
    if (value.isEmpty) {
      final existingDiscount = product.discountPercentage ?? 0.0;
      return existingDiscount >= _minDiscountPercentage;
    }

    final discount = double.tryParse(value);
    if (discount == null) return false;

    return discount >= _minDiscountPercentage &&
        discount <= _maxDiscountPercentage;
  }

  bool _allProductsHaveDiscount() {
    for (final product in _uniqueProducts) {
      // Skip blocked products
      if (_isProductBlocked(product)) continue;

      final controller = _individualControllers[product.id];
      final inputValue = controller?.text.trim() ?? '';

      if (inputValue.isNotEmpty) {
        // User entered a value, validate it
        final discount = double.tryParse(inputValue);
        if (discount == null ||
            discount < _minDiscountPercentage ||
            discount > _maxDiscountPercentage) {
          return false;
        }
      } else {
        // Field is empty, check existing discount
        final existingDiscount = product.discountPercentage ?? 0.0;
        if (existingDiscount < _minDiscountPercentage) {
          return false;
        }
      }
    }
    return true;
  }

  void _toggleBulkInput() {
    setState(() {
      _showBulkInput = !_showBulkInput;
      _errorMessage = null;
    });

    if (_showBulkInput) {
      _bulkAnimationController.forward();
    } else {
      _bulkAnimationController.reverse();
      _bulkDiscountController.clear();
    }

    HapticFeedback.selectionClick();
  }

  bool _validateBulkDiscountPercentage(String value) {
    if (value.isEmpty) return false;

    final discount = double.tryParse(value);
    if (discount == null) return false;

    return discount >= _minDiscountPercentage &&
        discount <= _maxDiscountPercentage;
  }

  void _applyBulkDiscount() async {
    if (_isApplyingBulk) return;

    final l10n = AppLocalizations.of(context);
    final discountText = _bulkDiscountController.text.trim();
    if (discountText.isEmpty) {
      _showErrorSnackBar(l10n.pleaseEnterDiscountPercentage);
      return;
    }

    final discount = double.tryParse(discountText);
    if (discount == null || !_validateBulkDiscountPercentage(discountText)) {
      _showErrorSnackBar(l10n.discountRangeError(
          _minDiscountPercentage, _maxDiscountPercentage));
      return;
    }

    setState(() {
      _isApplyingBulk = true;
      _errorMessage = null;
    });

    // Animate the application
    await Future.delayed(const Duration(milliseconds: 300));

    // Apply to all non-blocked products
    for (final product in _uniqueProducts) {
      if (_isProductBlocked(product)) continue;

      _getController(product.id).text = discount.toStringAsFixed(1);
      _productDiscounts[product.id] = discount;
    }

    setState(() {
      _isApplyingBulk = false;
      _showBulkInput = false;
    });

    _bulkAnimationController.reverse();
    _bulkDiscountController.clear();

    HapticFeedback.mediumImpact();
    _showSuccessSnackBar(l10n.bulkDiscountApplied(_uniqueProducts.length));
  }

  void _updateIndividualDiscount(String productId, String value) {
    final discount = double.tryParse(value);
    setState(() {
      _productDiscounts[productId] = discount ?? 0.0;
      _errorMessage = null;
    });
  }

  Future<void> _saveAndContinue() async {
    if (_isSaving) return;

    final l10n = AppLocalizations.of(context);

    // Check if all products have discount
    if (!_allProductsHaveDiscount()) {
      _showErrorSnackBar(l10n.allProductsMustHaveDiscount);
      return;
    }

    // Validate all discounts (skip blocked products)
    final invalidDiscounts = <String>[];
    for (final product in _uniqueProducts) {
      if (_isProductBlocked(product)) continue;

      final controller = _individualControllers[product.id];
      final value = controller?.text.trim() ?? '';

      if (!_validateDiscountPercentage(value, product)) {
        invalidDiscounts.add(value);
      }
    }

    if (invalidDiscounts.isNotEmpty) {
      _showErrorSnackBar(l10n.someDiscountsInvalid(
          _minDiscountPercentage, _maxDiscountPercentage));
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _updateProductsWithCampaign();
      _navigateToSuccessScreen();
    } catch (e) {
      setState(() {
        _errorMessage = l10n.failedToSaveCampaign(e.toString());
        _isSaving = false;
      });
      _showErrorSnackBar(_errorMessage!);
    }
  }

  Future<void> _updateProductsWithCampaign() async {
    final campaignId = widget.campaign['id'] as String;
    final shopId = widget.shopId;

    final validProducts =
        _uniqueProducts.where((p) => !_isProductBlocked(p)).toList();

    final productsPayload = validProducts.map((product) {
      double discount = _productDiscounts[product.id] ?? 0.0;
      // Fall back to valid existing discount if no new input
      if (discount < _minDiscountPercentage &&
          (product.discountPercentage ?? 0) >= _minDiscountPercentage) {
        discount = product.discountPercentage!.toDouble();
      }
      return {'productId': product.id, 'discount': discount};
    }).toList();

    final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('addProductsToCampaign');

    final result = await callable.call({
      'campaignId': campaignId,
      'shopId': shopId,
      'products': productsPayload,
    });

    if (result.data['success'] != true) {
      throw Exception('Failed to add products to campaign');
    }
  }

  void _navigateToSuccessScreen() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SellerPanelCampaignSuccessScreen(
          campaign: widget.campaign,
          selectedProducts: _uniqueProducts,
          appliedDiscounts: Map.from(_productDiscounts),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _errorColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        action: SnackBarAction(
          label: l10n.dismiss,
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ✅ CHANGE: Removed _removeSalePreference's use of product.reference!
  // Now uses explicit document reference — safe regardless of product source.
  Future<void> _removeSalePreference(Product product) async {
    final l10n = AppLocalizations.of(context);

    try {
      await _firestore.collection('shop_products').doc(product.id).update({
        'discountThreshold': FieldValue.delete(),
        'bulkDiscountPercentage': FieldValue.delete(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.salePreferenceRemovedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );

        // Note: if the product had a targeted listener, it will pick up this
        // change automatically and update _uniqueProducts via setState.
        // The listener will also self-cancel since the product is no longer blocked.
        // If for some reason the listener isn't active, update manually:
        if (!_blockedProductListeners.containsKey(product.id)) {
          setState(() {
            final index = _uniqueProducts.indexWhere((p) => p.id == product.id);
            if (index != -1) {
              _uniqueProducts[index] = product.copyWith(
                discountThreshold: null,
                bulkDiscountPercentage: null,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorRemovingSalePreference),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? _darkBackground : _surfaceColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildBulkDiscountSection(),
            _buildStatsHeader(),
            Expanded(child: _buildProductList()),
            if (_errorMessage != null) _buildErrorBanner(),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    return AppBar(
      elevation: 0,
      backgroundColor: dark ? _darkBackground : _cardColor,
      iconTheme: IconThemeData(color: dark ? Colors.white : _textPrimary),
      foregroundColor: dark ? Colors.white : _textPrimary,
      toolbarHeight: 60,
      leading: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: dark ? _darkCard : _surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          iconSize: 18,
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.configureDiscounts,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : _textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              l10n.productsSelected(_uniqueProducts.length),
              style: const TextStyle(
                fontSize: 10,
                color: _primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(
          height: 0.5,
          color: _borderColor,
        ),
      ),
    );
  }

  Widget _buildBulkDiscountSection() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? _darkCard : _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: _borderColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _primaryColor.withOpacity(0.15),
                    _primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primaryColor.withOpacity(0.2)),
              ),
              child: const Icon(
                Icons.discount_outlined,
                color: _primaryColor,
                size: 20,
              ),
            ),
            title: Text(
              l10n.bulkDiscount,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: dark ? Colors.white : _textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            subtitle: Text(
              l10n.applySameDiscountToAllProducts,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Container(
              decoration: BoxDecoration(
                color: dark ? _darkCard : _surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: IconButton(
                onPressed: _toggleBulkInput,
                icon: AnimatedRotation(
                  turns: _showBulkInput ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.expand_more,
                    color: dark ? Colors.white70 : _textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
            onTap: _toggleBulkInput,
          ),
          AnimatedBuilder(
            animation: _bulkAnimationController,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _bulkScaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: _borderColor,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _bulkDiscountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*')),
                            ],
                            decoration: InputDecoration(
                              labelText: l10n.discountPercentage,
                              labelStyle: const TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                              hintText: l10n.exampleDiscount,
                              hintStyle: TextStyle(
                                color: dark
                                    ? Colors.white70
                                    : _textSecondary.withOpacity(0.6),
                                fontSize: 12,
                              ),
                              suffixIcon: Container(
                                margin: const EdgeInsets.all(6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '%',
                                  style: TextStyle(
                                    color: _primaryColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _primaryColor,
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: dark
                                  ? _darkCard.withOpacity(0.5)
                                  : _surfaceColor.withOpacity(0.5),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              helperText: l10n.discountRange(
                                  _minDiscountPercentage,
                                  _maxDiscountPercentage),
                              helperStyle: const TextStyle(
                                color: _textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isApplyingBulk
                                ? [_textSecondary, _textSecondary]
                                : [
                                    _primaryColor,
                                    _primaryColor.withOpacity(0.8)
                                  ],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed:
                              _isApplyingBulk ? null : _applyBulkDiscount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isApplyingBulk
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.flash_on, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.apply,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final productsWithDiscount = _productDiscounts.values
        .where((discount) => discount >= _minDiscountPercentage)
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? _darkCard : _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              l10n.totalProducts,
              '${_uniqueProducts.length}',
              Icons.inventory_2_outlined,
              _primaryColor,
            ),
          ),
          Container(
            width: 0.5,
            height: 36,
            color: _borderColor,
          ),
          Expanded(
            child: _buildStatItem(
              l10n.withDiscount,
              '$productsWithDiscount',
              Icons.local_offer_outlined,
              _successColor,
            ),
          ),
          Container(
            width: 0.5,
            height: 36,
            color: _borderColor,
          ),
          Expanded(
            child: _buildStatItem(
              l10n.noDiscount,
              '${_uniqueProducts.length - productsWithDiscount}',
              Icons.remove_circle_outline,
              _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: _textSecondary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProductList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: _uniqueProducts.length,
      itemBuilder: (context, index) {
        final product = _uniqueProducts[index];
        return _buildProductCard(product, index);
      },
    );
  }

  Widget _buildProductCard(Product product, int index) {
    final l10n = AppLocalizations.of(context);
    final controller = _getController(product.id);
    final focusNode = _getFocusNode(product.id);
    final discount = _productDiscounts[product.id] ?? 0.0;
    final hasDiscount = discount >= _minDiscountPercentage;

    final isBlocked = _isProductBlocked(product);

    // Check for sale preference (buy X to get Y% discount)
    final hasSalePreference = product.discountThreshold != null &&
        product.bulkDiscountPercentage != null &&
        product.discountThreshold! > 0 &&
        product.bulkDiscountPercentage! > 0;

    // Check if product is part of a bundle
    final isInBundle = product.bundleIds.isNotEmpty;

    // Use original price if available, otherwise use current price
    final basePrice = product.originalPrice ?? product.price;
    final discountedPrice =
        hasDiscount ? basePrice * (1 - discount / 100) : basePrice;

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: dark ? _darkCard : _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDiscount
              ? _successColor.withOpacity(0.3)
              : _borderColor.withOpacity(0.5),
          width: hasDiscount ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Product Image
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _surfaceColor,
                border: Border.all(color: _borderColor.withOpacity(0.5)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: product.imageUrls.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrls.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: _surfaceColor,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _primaryColor,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: _surfaceColor,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: _textSecondary.withOpacity(0.5),
                            size: 20,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.image_outlined,
                        color: _textSecondary.withOpacity(0.5),
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Product Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: dark ? Colors.white : _textPrimary,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (product.originalPrice != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _textSecondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _textSecondary.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                l10n.originalPrice2,
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${discountedPrice.toStringAsFixed(2)} ${product.currency ?? ''}',
                        style: TextStyle(
                          color: hasDiscount ? _successColor : _primaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _successColor,
                                _successColor.withOpacity(0.8)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${discount.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Discount Input - Hide when blocked
                  if (!isBlocked)
                    SizedBox(
                      width: 120,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*')),
                          ],
                          onChanged: (value) =>
                              _updateIndividualDiscount(product.id, value),
                          decoration: InputDecoration(
                            labelText: l10n.discount,
                            labelStyle: const TextStyle(
                              color: _textSecondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                            hintText: '15.0',
                            hintStyle: TextStyle(
                              color: dark
                                  ? Colors.white70
                                  : _textSecondary.withOpacity(0.6),
                              fontSize: 12,
                            ),
                            suffixIcon: Container(
                              margin: const EdgeInsets.all(4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '%',
                                style: TextStyle(
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: _primaryColor,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: dark
                                ? _darkCard.withOpacity(0.5)
                                : _surfaceColor.withOpacity(0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  if (!isBlocked) const SizedBox(height: 8),

                  // Existing discount warning
                  if (product.discountPercentage != null &&
                      product.discountPercentage! > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (product.discountPercentage! >=
                                _minDiscountPercentage)
                            ? (dark
                                ? const Color(0xFF10B981).withOpacity(0.15)
                                : const Color(0xFF10B981).withOpacity(0.1))
                            : (dark
                                ? const Color(0xFFFF9500).withOpacity(0.15)
                                : const Color(0xFFFF9500).withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (product.discountPercentage! >=
                                  _minDiscountPercentage)
                              ? const Color(0xFF10B981).withOpacity(0.3)
                              : const Color(0xFFFF9500).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (product.discountPercentage! >=
                                    _minDiscountPercentage)
                                ? Icons.check_circle_outline
                                : Icons.warning_outlined,
                            size: 14,
                            color: (product.discountPercentage! >=
                                    _minDiscountPercentage)
                                ? (dark
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF059669))
                                : (dark
                                    ? Colors.white
                                    : const Color.fromARGB(211, 206, 111, 43)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (product.discountPercentage! >=
                                      _minDiscountPercentage)
                                  ? l10n.productHasValidDiscount(product
                                      .discountPercentage!
                                      .toStringAsFixed(1))
                                  : l10n.productDiscountBelowThreshold(
                                      product.discountPercentage!
                                          .toStringAsFixed(1),
                                      _minDiscountPercentage
                                          .toStringAsFixed(0)),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: (product.discountPercentage! >=
                                        _minDiscountPercentage)
                                    ? (dark
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF059669))
                                    : (dark
                                        ? Colors.white
                                        : const Color.fromARGB(
                                            211, 206, 111, 43)),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Sale preference warning
                  if (hasSalePreference) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.removeSalePreferenceToCreateBundle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: dark
                                        ? Colors.white
                                        : Colors.orange.shade700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 100,
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () => _removeSalePreference(product),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                l10n.remove,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Bundle warning
                  if (isInBundle && !hasSalePreference) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.purple.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 14,
                            color: Colors.purple.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.productInBundleCannotAddToCampaign,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: dark
                                    ? Colors.purple.shade200
                                    : Colors.purple.shade700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
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
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _errorColor.withOpacity(0.1),
            _errorColor.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: _errorColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _errorColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.error_outline,
              color: _errorColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: _errorColor.withOpacity(0.9),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    final l10n = AppLocalizations.of(context);
    final canContinue = _allProductsHaveDiscount();

    return AnimatedBuilder(
      animation: _fabAnimationController,
      builder: (context, child) {
        return SlideTransition(
          position: _fabSlideAnimation,
          child: ScaleTransition(
            scale: _fabScaleAnimation,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: (!canContinue || _isSaving)
                      ? [_textSecondary, _textSecondary]
                      : [_primaryColor, _primaryColor.withOpacity(0.8)],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FloatingActionButton.extended(
                  onPressed:
                      (!canContinue || _isSaving) ? null : _saveAndContinue,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  highlightElevation: 0,
                  hoverElevation: 0,
                  focusElevation: 0,
                  disabledElevation: 0,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.check_circle_outline,
                          size: 20,
                        ),
                  label: Text(
                    _isSaving ? l10n.savingCampaign : l10n.continueToSummary,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
