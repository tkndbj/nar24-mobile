import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../auth_service.dart';
import '../../utils/attribute_localization_utils.dart';
import 'login_modal.dart';
import 'package:shimmer/shimmer.dart';

class ProductOptionSelector extends StatefulWidget {
  final Product product;
  final bool isBuyNow;

  const ProductOptionSelector({
    Key? key,
    required this.product,
    this.isBuyNow = false,
  }) : super(key: key);

  @override
  _ProductOptionSelectorState createState() => _ProductOptionSelectorState();
}

class _ProductOptionSelectorState extends State<ProductOptionSelector> {
  final Map<String, dynamic> _selections = {};
  String? selectedColor;
  int selectedQuantity = 1;

  // Curtain dimension controllers
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final FocusNode _widthFocusNode = FocusNode();
  final FocusNode _heightFocusNode = FocusNode();

  // Sale preferences state
  Map<String, dynamic>? _salePreferences;

  // Fresh product state
  Product? _freshProduct;
  bool _isLoadingProduct = true;
  String? _loadError;

  // Track if user attempted to confirm without selecting all options
  bool _attemptedConfirm = false;

  // ✅ Use fresh product with fallback
  Product get _currentProduct => _freshProduct ?? widget.product;

  bool get hasColors => _currentProduct.colorImages.isNotEmpty;
  bool get hasDynamicOptions => _getSelectableAttributes().isNotEmpty;
  bool get isCurtain =>
      _currentProduct.subsubcategory.toLowerCase() == 'curtains';

  @override
  void initState() {
    super.initState();
    _fetchFreshProductData();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocusNode.dispose();
    _heightFocusNode.dispose();
    super.dispose();
  }

  // ========================================================================
  // FETCH FRESH PRODUCT DATA (Optimized - Single Read)
  // ========================================================================
  Future<void> _fetchFreshProductData() async {
    try {
      setState(() {
        _isLoadingProduct = true;
        _loadError = null;
      });

      // ✅ OPTIMIZATION: Try shop_products first (most common), single read
      final productDoc = await FirebaseFirestore.instance
          .collection('shop_products')
          .doc(widget.product.id)
          .get(const GetOptions(
              source: Source.server)); // Force server for fresh data

      DocumentSnapshot? validDoc;

      if (productDoc.exists) {
        validDoc = productDoc;
      } else {
        // Fallback to products collection (rare case)
        final productsDoc = await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.product.id)
            .get(const GetOptions(source: Source.server));

        if (productsDoc.exists) {
          validDoc = productsDoc;
        }
      }

      if (validDoc == null || !validDoc.exists) {
        setState(() {
          _loadError = 'Product not found';
          _isLoadingProduct = false;
        });
        return;
      }

      // Parse fresh product
      final freshProduct = Product.fromDocument(validDoc);

      setState(() {
        _freshProduct = freshProduct;
        _isLoadingProduct = false;
      });

      // Initialize after fresh data loaded
      _loadSalePreferencesFromProduct();
      _initializeDefaultSelections();
    } catch (e) {
      debugPrint('❌ Error fetching fresh product: $e');
      setState(() {
        _loadError = 'Failed to load product details';
        _isLoadingProduct = false;
      });
    }
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================
  void _initializeDefaultSelections() {
    for (final entry in _currentProduct.attributes.entries) {
      final value = entry.value;
      List<String> options = [];

      if (value is List) {
        options = value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList();
      } else if (value is String && value.isNotEmpty) {
        options = value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }

      // Auto-select single options
      if (options.length == 1) {
        _selections[entry.key] = options.first;
      }
    }

    // Auto-select default color if no color options
    if (!hasColors) {
      selectedColor = 'default';
    }
  }

  void _loadSalePreferencesFromProduct() {
    if (_currentProduct.maxQuantity != null ||
        _currentProduct.discountThreshold != null ||
        _currentProduct.bulkDiscountPercentage != null) {
      _salePreferences = {
        if (_currentProduct.maxQuantity != null)
          'maxQuantity': _currentProduct.maxQuantity,
        if (_currentProduct.discountThreshold != null)
          'discountThreshold': _currentProduct.discountThreshold,
        if (_currentProduct.bulkDiscountPercentage != null)
          'bulkDiscountPercentage': _currentProduct.bulkDiscountPercentage,
      };

      final maxAllowed = _getMaxQuantityAllowed();
      if (selectedQuantity > maxAllowed) {
        selectedQuantity = maxAllowed;
      }
    }
  }

  int _getMaxQuantityAllowed() {
    final stockQuantity = maxQty;
    if (_salePreferences == null) return stockQuantity;
    final maxQuantityFromPrefs = _salePreferences!['maxQuantity'] as int?;
    if (maxQuantityFromPrefs == null) return stockQuantity;
    return stockQuantity < maxQuantityFromPrefs
        ? stockQuantity
        : maxQuantityFromPrefs;
  }

  Map<String, List<String>> _getSelectableAttributes() {
    final Map<String, List<String>> selectableAttrs = {};

    // ✅ ADD: Keys that should NOT be selectable by buyers
    const nonSelectableKeys = {
      'clothingType',
      'clothingTypes',
      'pantFabricType',
      'pantFabricTypes',
      'gender',
      'clothingFit', // fit is also a product property, not a choice
    };

    for (final entry in _currentProduct.attributes.entries) {
      // ✅ ADD: Skip non-selectable attributes
      if (nonSelectableKeys.contains(entry.key)) {
        continue;
      }

      final value = entry.value;
      List<String> options = [];

      if (value is List) {
        options = value
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList();
      } else if (value is String && value.isNotEmpty) {
        options = value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }

      if (options.length > 1) {
        selectableAttrs[entry.key] = options;
      }
    }

    return selectableAttrs;
  }

  bool get isConfirmEnabled {
    if (isCurtain) {
      if (!_validateCurtainDimensions()) return false;
    }

    if (hasColors && selectedColor == null) return false;

    final selectableAttrs = _getSelectableAttributes();
    for (final key in selectableAttrs.keys) {
      if (_selections[key] == null) return false;
    }
    return true;
  }

  bool _validateCurtainDimensions() {
    final widthText = _widthController.text.trim();
    final heightText = _heightController.text.trim();

    if (widthText.isEmpty || heightText.isEmpty) return false;

    final width = double.tryParse(widthText);
    final height = double.tryParse(heightText);

    if (width == null || width <= 0) return false;
    if (height == null || height <= 0) return false;

    final maxWidth = _currentProduct.attributes['curtainMaxWidth'];
    final maxHeight = _currentProduct.attributes['curtainMaxHeight'];

    if (maxWidth != null) {
      final maxW = double.tryParse(maxWidth.toString()) ?? double.infinity;
      if (width > maxW) return false;
    }

    if (maxHeight != null) {
      final maxH = double.tryParse(maxHeight.toString()) ?? double.infinity;
      if (height > maxH) return false;
    }

    return true;
  }

  int get maxQty {
    if (selectedColor != null && selectedColor != 'default') {
      return _currentProduct.colorQuantities[selectedColor!] ?? 0;
    }
    return _currentProduct.quantity;
  }

  // ========================================================================
  // BUILD
  // ========================================================================
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      Future.microtask(() {
        Navigator.of(context).pop();
        showCupertinoModalPopup(
          context: context,
          builder: (_) => LoginPromptModal(authService: authService),
        );
      });
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final txtColor =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black;
    final isDark = theme.brightness == Brightness.dark;

    // Tablet detection for narrower width
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    // Helper to constrain width on tablets - aligned to bottom for proper modal behavior
    Widget wrapForTablet(Widget child) {
      if (!isTablet) return child;
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenWidth * 0.55),
          child: child,
        ),
      );
    }

    // ✅ LOADING STATE - Lightweight Shimmer
    if (_isLoadingProduct) {
      return wrapForTablet(
        CupertinoActionSheet(
          title: Text(
            l10n.selectOptions,
            style: const TextStyle(
              fontFamily: 'Figtree',
              fontWeight: FontWeight.w600,
            ),
          ),
          message: _buildLoadingShimmer(isDark),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDefaultAction: true,
            child: Text(
              l10n.cancel,
              style: TextStyle(
                  fontSize: 14, fontFamily: 'Figtree', color: txtColor),
            ),
          ),
        ),
      );
    }

    // ✅ ERROR STATE
    if (_loadError != null) {
      return wrapForTablet(
        CupertinoActionSheet(
          title: Text(
            l10n.selectOptions,
            style: const TextStyle(
              fontFamily: 'Figtree',
              fontWeight: FontWeight.w600,
            ),
          ),
          message: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDefaultAction: true,
            child: Text(
              l10n.close ?? 'Close',
              style: TextStyle(
                  fontSize: 14, fontFamily: 'Figtree', color: txtColor),
            ),
          ),
        ),
      );
    }

    // ✅ MAIN BUILD (Use fresh product)
    final selectableAttrs = _getSelectableAttributes();
    final safeMax = _getMaxQuantityAllowed();

    if (safeMax <= 0) {
      selectedQuantity = 1;
    } else {
      selectedQuantity = selectedQuantity.clamp(1, safeMax);
    }

    final totalStock = _currentProduct.quantity +
        _currentProduct.colorQuantities.values.fold(0, (sum, qty) => sum + qty);

    if (totalStock <= 0) {
      return wrapForTablet(
        CupertinoActionSheet(
          title: Text(
            l10n.selectOptions,
            style: const TextStyle(
              fontFamily: 'Figtree',
              fontWeight: FontWeight.w600,
            ),
          ),
          message: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  l10n.productOutOfStock(_currentProduct.productName),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDefaultAction: true,
            child: Text(
              l10n.close ?? 'Close',
              style: TextStyle(
                  fontSize: 14, fontFamily: 'Figtree', color: txtColor),
            ),
          ),
        ),
      );
    }

    return wrapForTablet(
      CupertinoActionSheet(
        title: Text(
          l10n.selectOptions,
          style: const TextStyle(
            fontFamily: 'Figtree',
            fontWeight: FontWeight.w600,
          ),
        ),
        message: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasColors) ...[
                _buildSectionTitle(l10n.selectColor, txtColor),
                const SizedBox(height: 8),
                _buildColorSelector(txtColor, l10n),
                if (_attemptedConfirm && selectedColor == null)
                  _buildFeedbackText(l10n.pleaseSelectColor),
                const SizedBox(height: 16),
              ],
              for (final entry in selectableAttrs.entries) ...[
                _buildSectionTitle(
                    AttributeLocalizationUtils.getLocalizedAttributeTitle(
                        entry.key, l10n),
                    txtColor),
                const SizedBox(height: 8),
                _buildAttributeSelector(entry.key, entry.value, txtColor, l10n),
                if (_attemptedConfirm && _selections[entry.key] == null)
                  _buildFeedbackText(l10n.pleaseSelectAnOption),
                const SizedBox(height: 16),
              ],
              if (isCurtain) ...[
                _buildCurtainDimensionsInput(l10n, txtColor),
                if (_attemptedConfirm &&
                    !_validateCurtainDimensions() &&
                    (_widthController.text.isEmpty ||
                        _heightController.text.isEmpty))
                  _buildFeedbackText(l10n.pleaseEnterValidDimensions),
              ] else ...[
                _buildSectionTitle(l10n.quantity, txtColor),
                const SizedBox(height: 8),
                _buildQuantitySelector(safeMax, l10n),
                if (_salePreferences != null &&
                    _salePreferences!['discountThreshold'] != null &&
                    _salePreferences!['bulkDiscountPercentage'] != null)
                  _buildSalePreferenceInfo(l10n, txtColor),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              if (isConfirmEnabled) {
                final result = <String, dynamic>{
                  if (hasColors) 'selectedColor': selectedColor,
                  ..._selections,
                };

                if (isCurtain) {
                  result['curtainWidth'] =
                      double.parse(_widthController.text.trim());
                  result['curtainHeight'] =
                      double.parse(_heightController.text.trim());
                  result['quantity'] = 1;
                } else {
                  result['quantity'] = selectedQuantity;
                }

                if (selectedColor != null && selectedColor != 'default') {
                  final colorImages =
                      _currentProduct.colorImages[selectedColor!];
                  if (colorImages != null && colorImages.isNotEmpty) {
                    result['selectedColorImage'] = colorImages.first;
                  }
                }

                Navigator.of(context).pop(result);
              } else {
                // Show feedback for missing selections
                setState(() => _attemptedConfirm = true);
              }
            },
            child: Text(
              l10n.confirm,
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
                color: isConfirmEnabled ? txtColor : Colors.grey,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          isDefaultAction: true,
          child: Text(
            l10n.cancel,
            style:
                TextStyle(fontSize: 14, fontFamily: 'Figtree', color: txtColor),
          ),
        ),
      ),
    );
  }

  // ========================================================================
  // SHIMMER LOADING
  // ========================================================================
  Widget _buildLoadingShimmer(bool isDark) {
    final baseColor =
        isDark ? const Color.fromARGB(255, 46, 43, 66) : Colors.grey[300]!;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color selector shimmer
            Row(
              children: List.generate(
                3,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Options shimmer
            Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // UI BUILDERS
  // ========================================================================
  Widget _buildCurtainDimensionsInput(AppLocalizations l10n, Color txtColor) {
    final maxWidth = _currentProduct.attributes['curtainMaxWidth'];
    final maxHeight = _currentProduct.attributes['curtainMaxHeight'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
            l10n.curtainDimensions ?? 'Curtain Dimensions', txtColor),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      focusNode: _widthFocusNode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.maxWidth ?? 'Width',
                        hintText:
                            '${l10n.enterValue ?? "Enter"} (${l10n.metersUnit ?? "m"})',
                        suffixText: l10n.metersUnit ?? 'm',
                        helperText: maxWidth != null
                            ? '${l10n.maximum ?? "Max"}: $maxWidth ${l10n.metersUnit ?? "m"}'
                            : null,
                        helperStyle:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.orange, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.swap_vert, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      focusNode: _heightFocusNode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.maxHeight ?? 'Height',
                        hintText:
                            '${l10n.enterValue ?? "Enter"} (${l10n.metersUnit ?? "m"})',
                        suffixText: l10n.metersUnit ?? 'm',
                        helperText: maxHeight != null
                            ? '${l10n.maximum ?? "Max"}: $maxHeight ${l10n.metersUnit ?? "m"}'
                            : null,
                        helperStyle:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Colors.orange, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_widthController.text.isNotEmpty && maxWidth != null) ...[
                const SizedBox(height: 8),
                if (double.tryParse(_widthController.text) != null &&
                    double.parse(_widthController.text) >
                        double.parse(maxWidth.toString()))
                  Text(
                    '${l10n.widthExceedsMaximum ?? "Width exceeds maximum"}!',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
              if (_heightController.text.isNotEmpty && maxHeight != null) ...[
                const SizedBox(height: 8),
                if (double.tryParse(_heightController.text) != null &&
                    double.parse(_heightController.text) >
                        double.parse(maxHeight.toString()))
                  Text(
                    '${l10n.heightExceedsMaximum ?? "Height exceeds maximum"}!',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalePreferenceInfo(AppLocalizations l10n, Color txtColor) {
    final discountThreshold = _salePreferences!['discountThreshold'] as int;
    final bulkDiscountPercentage =
        _salePreferences!['bulkDiscountPercentage'] as int;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Center(
        child: Text(
          selectedQuantity >= discountThreshold
              ? '${l10n.discountApplied ?? 'Discount applied'}: $bulkDiscountPercentage%'
              : switch (l10n.localeName) {
                  'tr' =>
                    '$discountThreshold tane alırsan %$bulkDiscountPercentage indirim kazanırsın!',
                  'ru' =>
                    'Если купишь $discountThreshold штук, получишь скидку $bulkDiscountPercentage%!',
                  _ =>
                    'Buy $discountThreshold for $bulkDiscountPercentage% discount!',
                },
          style: TextStyle(
            fontSize: 13,
            color: selectedQuantity >= discountThreshold
                ? Colors.green
                : Colors.orange,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color txtColor) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.orange,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildFeedbackText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.red.shade400,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildColorSelector(Color txtColor, AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (_currentProduct.imageUrls.isNotEmpty)
            _buildColorThumb(
              key: 'default',
              url: _currentProduct.imageUrls.first,
              isSelected: selectedColor == 'default',
              disabled: _currentProduct.quantity == 0,
              onTap: () => setState(() => selectedColor = 'default'),
              txtColor: txtColor,
              l10n: l10n,
            ),
          ..._currentProduct.colorImages.entries.map((e) {
            final qty = _currentProduct.colorQuantities[e.key] ?? 0;
            return _buildColorThumb(
              key: e.key,
              url: e.value.first,
              isSelected: selectedColor == e.key,
              disabled: qty == 0,
              onTap: () => setState(() => selectedColor = e.key),
              txtColor: txtColor,
              l10n: l10n,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttributeSelector(String attributeKey, List<String> options,
      Color txtColor, AppLocalizations l10n) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: options.map((option) {
        final isSelected = _selections[attributeKey] == option;
        final localizedOption =
            AttributeLocalizationUtils.getLocalizedSingleValue(
                attributeKey, option, l10n);
        return _buildAttributeChip(
          label: localizedOption,
          originalValue: option,
          isSelected: isSelected,
          onTap: () => setState(() {
            _selections[attributeKey] = option;
          }),
          txtColor: txtColor,
        );
      }).toList(),
    );
  }

  Widget _buildQuantitySelector(int safeMax, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(CupertinoIcons.minus_circle),
          onPressed: selectedQuantity > 1
              ? () => setState(() => selectedQuantity--)
              : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$selectedQuantity',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(CupertinoIcons.plus_circle),
          onPressed: selectedQuantity < safeMax
              ? () => setState(() => selectedQuantity++)
              : null,
        ),
      ],
    );
  }

  Widget _buildColorThumb({
    required String key,
    required String url,
    required bool isSelected,
    required bool disabled,
    required VoidCallback onTap,
    required Color txtColor,
    required AppLocalizations l10n,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: disabled
                ? Colors.grey.shade400
                : (isSelected ? Colors.orange : Colors.grey),
            width: isSelected ? 3 : 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ColorFiltered(
                  colorFilter: disabled
                      ? ColorFilter.mode(Colors.grey, BlendMode.saturation)
                      : ColorFilter.mode(
                          Colors.transparent, BlendMode.multiply),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.error, color: Colors.red),
                    ),
                  ),
                ),
                if (disabled)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    alignment: Alignment.center,
                    child: Text(
                      l10n.noStock,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (isSelected && !disabled)
                  Container(
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttributeChip({
    required String label,
    required String originalValue,
    required bool isSelected,
    required VoidCallback onTap,
    required Color txtColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.orange : txtColor,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
