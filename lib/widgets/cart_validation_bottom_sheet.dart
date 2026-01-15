// lib/widgets/cart_validation_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../generated/l10n/app_localizations.dart';
import '../models/product.dart';
import '../utils/attribute_localization_utils.dart';

class CartValidationBottomSheet extends StatefulWidget {
  final Map<String, dynamic> errors;  // ✅ Changed from Map<String, String>
  final Map<String, dynamic> warnings; // ✅ Changed from Map<String, String>
  final List<Map<String, dynamic>> validatedItems; // ✅ NEW: From Cloud Function
  final List<Map<String, dynamic>> cartItems;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  const CartValidationBottomSheet({
    Key? key,
    required this.errors,
    required this.warnings,
    required this.validatedItems, // ✅ NEW
    required this.cartItems,
    required this.onContinue,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<CartValidationBottomSheet> createState() =>
      _CartValidationBottomSheetState();
}

class _CartValidationBottomSheetState
    extends State<CartValidationBottomSheet> {
  final Set<String> _confirmedWarnings = {};

  bool get _hasErrors => widget.errors.isNotEmpty;
  bool get _hasWarnings => widget.warnings.isNotEmpty;
  bool get _allWarningsConfirmed =>
      !_hasWarnings || _confirmedWarnings.length == widget.warnings.length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          _buildDragHandle(isDark),

          // Header
          _buildHeader(l10n, isDark),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error Products (Blocking)
                  if (_hasErrors) ...[
                    _buildSectionTitle(
                      l10n.validationErrorsTitle,
                      Icons.error_outline,
                      Colors.red,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    ...widget.errors.entries.map((entry) {
                      return _buildErrorProductCard(
                        entry.key,
                        entry.value,
                        l10n,
                        isDark,
                      );
                    }).toList(),
                    const SizedBox(height: 24),
                  ],

                  // Warning Products (Non-blocking)
                  if (_hasWarnings) ...[
                    _buildSectionTitle(
                      l10n.validationWarningsTitle,
                      Icons.warning_amber_rounded,
                      Colors.orange,
                      isDark,
                    ),
                    const SizedBox(height: 12),
                    ...widget.warnings.entries.map((entry) {
                      return _buildWarningProductCard(
                        entry.key,
                        entry.value,
                        l10n,
                        isDark,
                      );
                    }).toList(),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),

          // Action Buttons
          _buildActionButtons(l10n, isDark),
        ],
      ),
    );
  }

  Widget _buildDragHandle(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 20),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hasErrors
                  ? Colors.red.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _hasErrors ? Icons.error_outline : Icons.warning_amber_rounded,
              color: _hasErrors ? Colors.red : Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.validationIssuesDetected,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildHeaderSubtitle(l10n),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.grey.shade600),
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }

  String _buildHeaderSubtitle(AppLocalizations l10n) {
    if (_hasErrors && _hasWarnings) {
      return l10n.validationBothIssues(
          widget.errors.length, widget.warnings.length);
    } else if (_hasErrors) {
      return l10n.validationErrorsCount(widget.errors.length);
    } else {
      return l10n.validationWarningsCount(widget.warnings.length);
    }
  }

  Widget _buildSectionTitle(
      String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

Widget _buildErrorProductCard(
  String productId,
  Map<String, dynamic> errorData,
  AppLocalizations l10n,
  bool isDark,
) {
  final product = _findProduct(productId);
  
  // ✅ Find validated item to get color image
  final validatedItem = _findValidatedItem(productId);
  final colorImage = validatedItem?['colorImage'] as String?;
  
  // ✅ BULLETPROOF: Localize error message with fallback
  String errorMessage;
  try {
    errorMessage = _localizeValidationMessage(errorData, l10n);
  } catch (e) {
    debugPrint('❌ Failed to localize error for $productId: $e');
    errorMessage = 'Product unavailable';
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: isDark
          ? const Color(0xFF252332)
          : Colors.red.shade50.withOpacity(0.5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.red.withOpacity(0.3),
        width: 1.5,
      ),
    ),
    child: Column(
      children: [
        // Product Info
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ✅ Product Image (with color image priority)
              _buildProductImage(colorImage, product, 60, isDark),
              const SizedBox(width: 12),

              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product?.productName ?? l10n.unknownProduct,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // ✅ Show selected color if available
                    if (validatedItem?['selectedColor'] != null) ...[
  const SizedBox(height: 4),
  Text(
    '${l10n.color}: ${AttributeLocalizationUtils.localizeColorName(validatedItem!['selectedColor'], l10n)}',
    style: GoogleFonts.inter(
      fontSize: 11,
      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
    ),
  ),
],
                    
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, size: 12, color: Colors.red),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              errorMessage,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.red,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Notice Banner (unchanged)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.validationWillBeRemoved,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildWarningProductCard(
  String productId,
  Map<String, dynamic> warningData,
  AppLocalizations l10n,
  bool isDark,
) {
  final product = _findProduct(productId);
  final isConfirmed = _confirmedWarnings.contains(productId);

  // ✅ Find validated item to get color image
  final validatedItem = _findValidatedItem(productId);
  final colorImage = validatedItem?['colorImage'] as String?;
  
  // ✅ BULLETPROOF: Localize warning message with fallback
  String warningMessage;
  try {
    warningMessage = _localizeValidationMessage(warningData, l10n);
  } catch (e) {
    debugPrint('❌ Failed to localize warning for $productId: $e');
    warningMessage = 'Price or availability changed';
  }
  
  // ✅ BULLETPROOF: Parse warning for old/new values display with fallback
  Map<String, String>? parsedWarning;
  try {
    parsedWarning = _parseLocalizedWarning(warningData, l10n);
  } catch (e) {
    debugPrint('❌ Failed to parse warning for $productId: $e');
    parsedWarning = null;
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: isDark
          ? const Color(0xFF252332)
          : Colors.orange.shade50.withOpacity(0.5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isConfirmed
            ? const Color(0xFF00A86B).withOpacity(0.5)
            : Colors.orange.withOpacity(0.3),
        width: 1.5,
      ),
    ),
    child: Column(
      children: [
        // Product Info
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ✅ Product Image (with color image priority)
              _buildProductImage(colorImage, product, 60, isDark),
              const SizedBox(width: 12),

              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product?.productName ?? l10n.unknownProduct,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    // ✅ Show selected color if available
                   if (validatedItem?['selectedColor'] != null) ...[
  const SizedBox(height: 4),
  Text(
    '${l10n.color}: ${AttributeLocalizationUtils.localizeColorName(validatedItem!['selectedColor'], l10n)}',
    style: GoogleFonts.inter(
      fontSize: 11,
      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
    ),
  ),
],
                    
                    const SizedBox(height: 8),

                    // Warning Details
                    if (parsedWarning != null)
                      _buildWarningDetail(
                        parsedWarning['label']!,
                        parsedWarning['oldValue']!,
                        parsedWarning['newValue']!,
                        isDark,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 12, color: Colors.orange),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                warningMessage,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Confirmation Checkbox
        InkWell(
          onTap: () {
            setState(() {
              if (isConfirmed) {
                _confirmedWarnings.remove(productId);
              } else {
                _confirmedWarnings.add(productId);
              }
            });
          },
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isConfirmed
                  ? const Color(0xFF00A86B).withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? const Color(0xFF00A86B)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isConfirmed
                          ? const Color(0xFF00A86B)
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isConfirmed
                      ? const Icon(Icons.check,
                          size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.validationAcceptChange,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isConfirmed
                          ? const Color(0xFF00A86B)
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildWarningDetail(
    String label,
    String oldValue,
    String newValue,
    bool isDark,    
  ) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.orange.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.orange.shade800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Old Value
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.oldLabel,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        oldValue,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: Colors.orange.shade600,
                ),
              ),
              // New Value
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.newLabel,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        newValue,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade900,
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
    );
  }

 Widget _buildProductImage(
  String? colorImage, // ✅ NEW: Priority image (color-specific)
  Product? product, 
  double size, 
  bool isDark,
) {
  // ✅ Determine which image to show
  String? imageUrl;
  
  if (colorImage != null && colorImage.isNotEmpty) {
    imageUrl = colorImage; // ✅ Use color image if available
  } else if (product != null && product.imageUrls.isNotEmpty) {
    imageUrl = product.imageUrls.first; // ✅ Fallback to default image
  }

  if (imageUrl == null || imageUrl.isEmpty) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.image_not_supported,
        color: Colors.grey.shade500,
        size: size * 0.4,
      ),
    );
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: CachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        child: Center(
          child: SizedBox(
            width: size * 0.3,
            height: size * 0.3,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.grey.shade400),
            ),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        child: Icon(
          Icons.broken_image,
          color: Colors.grey.shade500,
          size: size * 0.4,
        ),
      ),
    ),
  );
}

  Widget _buildActionButtons(AppLocalizations l10n, bool isDark) {
    final hasValidProducts = widget.cartItems.length > widget.errors.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Continue Button
            if (hasValidProducts)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      (_hasWarnings && !_allWarningsConfirmed) || !hasValidProducts
                          ? null
                          : widget.onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A86B),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _hasErrors ? Icons.remove_shopping_cart : Icons.check_circle,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _hasErrors
                            ? l10n.validationContinueWithoutErrors
                            : l10n.validationContinueWithChanges,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Cancel Button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.cancel,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Product? _findProduct(String productId) {
    try {
      final item = widget.cartItems.firstWhere(
        (item) => item['productId'] == productId,
      );
      return item['product'] as Product?;
    } catch (e) {
      return null;
    }
  }

  /// Find validated item by productId
Map<String, dynamic>? _findValidatedItem(String productId) {
  try {
    return widget.validatedItems.firstWhere(
      (item) => item['productId'] == productId,
    );
  } catch (e) {
    return null;
  }
}

/// ✅ BULLETPROOF: Localize validation messages with safe type handling
String _localizeValidationMessage(Map<String, dynamic> message, AppLocalizations l10n) {
  // ✅ CRITICAL: Handle null or malformed messages
  if (message.isEmpty) return 'Unknown error';
  
  final key = message['key']?.toString() ?? 'unknown';
  final params = message['params'] is Map<String, dynamic> 
      ? message['params'] as Map<String, dynamic> 
      : <String, dynamic>{};
  
  // ✅ Helper functions for safe type extraction
  int _safeInt(String key, [int defaultValue = 0]) {
    final value = params[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    if (value is num) return value.toInt();
    return defaultValue;
  }
  
  String _safeString(String key, [String defaultValue = '']) {
    final value = params[key];
    if (value == null) return defaultValue;
    return value.toString();
  }
  
  try {
    switch (key) {
      // ========== ERRORS ==========
      case 'product_not_available':
        return l10n.productNotAvailable;
        
      case 'product_unavailable':
        return l10n.productCurrentlyUnavailable;
        
      case 'out_of_stock':
        return l10n.outOfStock;
        
      case 'insufficient_stock':
        final available = _safeInt('available', 0);
        final requested = _safeInt('requested', 0);
        return l10n.insufficientStock(available, requested);
        
      case 'max_quantity_exceeded':
        final maxQuantity = _safeInt('maxQuantity', 1);
        return l10n.maxQuantityExceeded(maxQuantity);
      
      // ========== WARNINGS ==========
      case 'price_changed':
        final currency = _safeString('currency', 'TL');
        final oldPrice = _safeString('oldPrice', '0.00');
        final newPrice = _safeString('newPrice', '0.00');
        return l10n.priceChanged(currency, oldPrice, newPrice);
        
      case 'bundle_price_changed':
        final currency = _safeString('currency', 'TL');
        final oldPrice = _safeString('oldPrice', '0.00');
        final newPrice = _safeString('newPrice', '0.00');
        return l10n.bundlePriceChanged(currency, oldPrice, newPrice);
        
      case 'discount_updated':
        final oldDiscount = _safeInt('oldDiscount', 0);
        final newDiscount = _safeInt('newDiscount', 0);
        return l10n.discountUpdated(oldDiscount, newDiscount);

      case 'bundle_no_longer_available':
  return l10n.bundleNoLongerAvailable;
        
      case 'discount_threshold_changed':
        final oldThreshold = _safeInt('oldThreshold', 0);
        final newThreshold = _safeInt('newThreshold', 0);
        return l10n.discountThresholdChanged(oldThreshold, newThreshold);
        
      case 'max_quantity_reduced':
        final oldMax = _safeInt('oldMax', 0);
        final newMax = _safeInt('newMax', 0);
        return l10n.maxQuantityReduced(oldMax, newMax);
      
      // ========== SPECIAL CASES ==========
      case 'reservation_failed':
        return l10n.reservationFailed ?? 'Failed to reserve stock. Please try again.';
      
      case 'legacy_message':
        return _safeString('message', 'Unknown error');
        
      case 'unknown':
      default:
        // ✅ Graceful fallback for unknown error types
        final fallbackMessage = _safeString('message');
        if (fallbackMessage.isNotEmpty) return fallbackMessage;
        
        // ✅ Last resort: Show key for debugging
        return 'Validation error: $key';
    }
  } catch (e) {
    debugPrint('❌ Error localizing message: $e, key: $key, params: $params');
    return 'Validation error occurred';
  }
}

Map<String, String>? _parseLocalizedWarning(
  Map<String, dynamic> warningData,
  AppLocalizations l10n,
) {
  // ✅ CRITICAL: Validate input
  if (warningData.isEmpty) return null;
  
  final key = warningData['key']?.toString() ?? 'unknown';
  final params = warningData['params'] is Map<String, dynamic>
      ? warningData['params'] as Map<String, dynamic>
      : <String, dynamic>{};
  
  // ✅ Helper for safe string extraction
  String _safeString(String key, [String defaultValue = '0']) {
    final value = params[key];
    if (value == null) return defaultValue;
    return value.toString();
  }
  
  try {
    switch (key) {
      case 'price_changed':
      case 'bundle_price_changed':
        final currency = _safeString('currency', 'TL');
        final oldPrice = _safeString('oldPrice', '0.00');
        final newPrice = _safeString('newPrice', '0.00');
        
        return {
          'label': key == 'price_changed' ? l10n.price : l10n.bundlePrice,
          'oldValue': '$currency $oldPrice',
          'newValue': '$currency $newPrice',
        };
      
      case 'discount_updated':
        final oldDiscount = _safeString('oldDiscount', '0');
        final newDiscount = _safeString('newDiscount', '0');
        
        return {
          'label': l10n.discount,
          'oldValue': '$oldDiscount%',
          'newValue': '$newDiscount%',
        };

      case 'bundle_no_longer_available':
  final currency = _safeString('currency', 'TL');
  final bundlePrice = _safeString('bundlePrice', '0.00');
  final regularPrice = _safeString('regularPrice', '0.00');
  
  return {
    'label': l10n.bundleNoLongerAvailableTitle,
    'oldValue': '$bundlePrice $currency',
    'newValue': '$regularPrice $currency',
  };
      
      case 'discount_threshold_changed':
        final oldThreshold = _safeString('oldThreshold', '0');
        final newThreshold = _safeString('newThreshold', '0');
        
        return {
          'label': l10n.discountThreshold,
          'oldValue': '${l10n.buy} $oldThreshold+',
          'newValue': '${l10n.buy} $newThreshold+',
        };
      
      case 'max_quantity_reduced':
        final oldMax = _safeString('oldMax', '0');
        final newMax = _safeString('newMax', '0');
        
        return {
          'label': l10n.maxQuantity,
          'oldValue': oldMax,
          'newValue': newMax,
        };
      
      default:
        return null;
    }
  } catch (e) {
    debugPrint('❌ Error parsing warning: $e, key: $key');
    return null;
  }
}
}