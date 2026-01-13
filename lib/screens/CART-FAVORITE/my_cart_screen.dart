// lib/screens/CART-FAVORITE/my_cart_screen.dart - REFACTORED v3.0 (Simplified + Fast)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/product_card_shimmer.dart';
import '../PAYMENT-RECEIPT/product_payment_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../market_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/cart_validation_bottom_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/sales_config_service.dart';
import 'package:shimmer/shimmer.dart';

class MyCartScreen extends StatefulWidget {
  const MyCartScreen({Key? key}) : super(key: key);

  @override
  _MyCartScreenState createState() => _MyCartScreenState();
}

class _MyCartScreenState extends State<MyCartScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool> _selectedProducts = {};
  bool _isValidating = false;
  CartProvider? _cartProvider;
  final SalesConfigService _salesConfigService = SalesConfigService();

  // Pull-to-refresh cooldown (30 seconds)
  static const Duration _refreshCooldown = Duration(seconds: 30);
  DateTime? _lastRefreshTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_cartProvider == null) {
      _cartProvider = Provider.of<CartProvider>(context, listen: false);

      // ✅ SIMPLE: Just initialize, listener is handled by provider
      if (!_cartProvider!.isInitialized) {
        _cartProvider!.initializeCartIfNeeded();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && _cartProvider != null) {
          _syncSelections(_cartProvider!.cartItems);
          _updateTotalsForCurrentSelection();
          setState(() {});
        }
      });

      _cartProvider!.cartItemsNotifier.addListener(_handleCartItemsChanged);
    }
  }

  void _handleCartItemsChanged() {
    if (!mounted) return;

    setState(() {
      _syncSelections(_cartProvider!.cartItems);
    });
    _updateTotalsForCurrentSelection();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // ✅ Keep lifecycle management (battery optimization)
    if (state == AppLifecycleState.paused) {
      _cartProvider?.disableLiveUpdates();
    } else if (state == AppLifecycleState.resumed) {
      // ✅ Re-enable listener on resume
      if (FirebaseAuth.instance.currentUser != null &&
          _cartProvider?.isInitialized == true) {
        _cartProvider?.enableLiveUpdates();
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _cartProvider?.loadMoreItems();
    }
  }

  /// Handles pull-to-refresh with 30-second cooldown.
  /// Returns immediately if cooldown hasn't elapsed, showing a snackbar.
  Future<void> _handleRefresh() async {
    if (_cartProvider == null) return;

    final now = DateTime.now();

    // Check cooldown
    if (_lastRefreshTime != null) {
      final elapsed = now.difference(_lastRefreshTime!);
      if (elapsed < _refreshCooldown) {
        final remaining = _refreshCooldown - elapsed;
        final seconds = remaining.inSeconds + 1; // +1 for user-friendly rounding
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          _showSnackBar(
            '${l10n.pleaseWait} ($seconds s)',
            isError: false,
          );
        }
        return;
      }
    }

    // Perform refresh
    _lastRefreshTime = now;
    await _cartProvider!.refresh();

    // Sync selections and update totals after refresh
    if (mounted) {
      _syncSelections(_cartProvider!.cartItems);
      _updateTotalsForCurrentSelection();
    }
  }

  @override
  void dispose() {
    _cartProvider?.cartItemsNotifier.removeListener(_handleCartItemsChanged);
    _cartProvider?.disableLiveUpdates();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  // ========================================================================
  // CART OPERATIONS
  // ========================================================================

  Future<void> _updateQuantity(String productId, int newQuantity) async {
    if (_cartProvider == null) return;

    final result = await _cartProvider!.updateQuantity(productId, newQuantity);

    if (result != 'Quantity updated' && result != 'Removed from cart') {
      _showSnackBar(result, isError: true);
    }
  }

  Future<void> _removeItem(String productId) async {
    if (_cartProvider == null) return;

    final result = await _cartProvider!.removeFromCart(productId);

    if (result == 'Removed from cart') {
      _selectedProducts.remove(productId);
      _updateTotalsForCurrentSelection();
    } else {
      _showSnackBar(result, isError: true);
    }
  }

  Future<void> _deleteSelectedProducts() async {
    if (_cartProvider == null) return;
    final l10n = AppLocalizations.of(context);

    final selectedIds = _selectedProducts.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedIds.isEmpty) {
      _showSnackBar(l10n.noItemsSelected, isError: true);
      return;
    }

    final result = await _cartProvider!.removeMultipleFromCart(selectedIds);

    if (result == 'Products removed from cart') {
      setState(() {
        for (var id in selectedIds) {
          _selectedProducts.remove(id);
        }
      });
      _updateTotalsForCurrentSelection();
      _showSnackBar(l10n.itemsRemoved);
    } else {
      _showSnackBar(result, isError: true);
    }
  }

  List<Map<String, dynamic>> _prepareItemsForPayment(List<Map<String, dynamic>> cartItems) {
  return cartItems.map((item) {
    final result = Map<String, dynamic>.from(item);
    
    // Build selectedAttributes from cartData (same format as "buy it now")
    final cartData = item['cartData'] as Map<String, dynamic>?;
    final Map<String, dynamic> selectedAttributes = {};
    
    // Add selectedColor if present
    final selectedColor = item['selectedColor'] ?? cartData?['selectedColor'];
    if (selectedColor != null && selectedColor != '') {
      selectedAttributes['selectedColor'] = selectedColor;
    }
    
    // Add dynamic attributes from cartData['attributes']
    if (cartData?['attributes'] is Map) {
      final attrs = cartData!['attributes'] as Map<String, dynamic>;
      attrs.forEach((key, value) {
        if (value != null && value != '' && (value is! List || (value).isNotEmpty)) {
          selectedAttributes[key] = value;
        }
      });
    }
    
    // Set selectedAttributes (matching "buy it now" structure)
    if (selectedAttributes.isNotEmpty) {
      result['selectedAttributes'] = selectedAttributes;
    }
    
    return result;
  }).toList();
}

  Future<void> _proceedToCheckout() async {
    if (_cartProvider == null) return;
    final l10n = AppLocalizations.of(context);

    final selectedIds = _selectedProducts.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedIds.isEmpty) {
      _showSnackBar(l10n.pleaseSelectItemsToCheckout, isError: true);
      return;
    }

    // ✅ Set loading state (no dialog)
    setState(() {
      _isValidating = true;
    });

    try {
      try {
      final salesConfig = await _salesConfigService.refreshConfig();
      if (salesConfig.salesPaused) {
        if (mounted) {
          setState(() {
            _isValidating = false;
          });
        }
        _showSalesPausedDialog(salesConfig.pauseReason);
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Could not verify sales status: $e');
      // Continue with checkout - fail-open approach
      // Change to return here if you want fail-closed
    }
      // ✅ Validate with Cloud Function (fresh data)
      final validation = await _cartProvider!.validateForPayment(
        selectedIds,
        reserveStock: false,
      );

      // ✅ Clear loading state
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }

      // ✅ CHECK FOR SYSTEM ERROR (validation service failed)
      if (validation['errors'] is Map &&
          (validation['errors'] as Map).containsKey('_system')) {
        final systemError = (validation['errors'] as Map)['_system'];

        if (systemError['key'] == 'validation_service_unavailable') {
          _showSnackBar(
            l10n.serviceUnavailable ??
                'Service temporarily unavailable. Please try again.',
            isError: true,
          );
          return;
        }
      }

      if (validation['isValid'] == true &&
          (validation['warnings'] as Map).isEmpty) {
        // ✅ No issues - proceed directly to payment
        final totals = await _cartProvider!
            .calculateCartTotals(selectedProductIds: selectedIds);
        final rawItems = await _cartProvider!.fetchAllSelectedItems(selectedIds);
final items = _prepareItemsForPayment(rawItems);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductPaymentScreen(
                items: items,
                totalPrice: totals.total,
              ),
            ),
          );
        }
      } else {
        // ✅ Show validation bottom sheet
        final errors = validation['errors'] as Map<String, dynamic>;
        final warnings = validation['warnings'] as Map<String, dynamic>;
        final validatedItems =
            validation['validatedItems'] as List<dynamic>? ?? [];
        final rawItems = await _cartProvider!.fetchAllSelectedItems(selectedIds);
final items = _prepareItemsForPayment(rawItems);

        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            isDismissible: false,
            builder: (bottomSheetContext) => CartValidationBottomSheet( 
              errors: errors,
              warnings: warnings,
              validatedItems: validatedItems.cast<Map<String, dynamic>>(),
              cartItems: items,
              onContinue: () async {
                Navigator.pop(bottomSheetContext);

                // ✅ FIX: Show loading during cache update
                setState(() {
                  _isValidating = true;
                });

                // ✅ Update cart cache with fresh values
                if (validatedItems.isNotEmpty) {
                  await _cartProvider!.updateCartCacheFromValidation(
                    validatedItems.cast<Map<String, dynamic>>(),
                  );
                }

                // Remove error items from selection
                for (final productId in errors.keys) {
                  _selectedProducts.remove(productId);
                }

                // ✅ FIX: Use validatedItems instead of recalculating
                final validIds = validatedItems
                    .map((item) => item['productId'] as String)
                    .toList();

                if (mounted) {
                  setState(() {
                    _isValidating = false;
                  });
                }

                if (validIds.isNotEmpty) {
                  // ✅ Get fresh items after cache update
                  final rawValidCartItems = await _cartProvider!.fetchAllSelectedItems(validIds);
final validCartItems = _prepareItemsForPayment(rawValidCartItems);

                  // ✅ Calculate totals from validated items (which have fresh prices)
                  final totals = await _cartProvider!
                      .calculateCartTotals(selectedProductIds: validIds);

                  if (mounted) {
                    // ✅ FIX: Navigate to payment immediately
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductPaymentScreen(
                          items: validCartItems,
                          totalPrice: totals.total,
                        ),
                      ),
                    );
                  }
                } else {
                  _showSnackBar(
                    l10n.noValidItemsToCheckout,
                    isError: true,
                  );
                }
              },
              onCancel: () => Navigator.pop(bottomSheetContext),
            ),
          );
        }
      }
    } catch (e) {
      // ✅ Clear loading on error
      if (mounted) {
        setState(() {
          _isValidating = false;
        });
      }

      debugPrint('❌ Checkout validation error: $e');
      _showSnackBar(
        l10n.validationFailed ?? 'Validation failed. Please try again.',
        isError: true,
      );
    }
  }

  void _updateTotalsForCurrentSelection() {
  final selectedIds = _selectedProducts.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toList();
  _cartProvider?.updateTotalsForSelection(selectedIds);
}

  void _showSalesPausedDialog(String? reason) {
  final l10n = AppLocalizations.of(context);
  
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.pause_circle_outline,
          color: Colors.orange,
          size: 48,
        ),
      ),
      title: Text(
        l10n.salesPausedTitle ?? 'Sales Temporarily Paused',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: Text(
        reason?.isNotEmpty == true
            ? reason!
            : (l10n.salesPausedMessage ?? 
               'We are currently not accepting orders. Please try again later.'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              l10n.understood ?? 'Understood',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTotalsShimmer(AppLocalizations l10n, int itemCount) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.total,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Shimmer.fromColors(
            baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
            child: Container(
              width: 120,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
      Text(
        '$itemCount ${l10n.items}',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
    ],
  );
}

  // ========================================================================
  // UI BUILDERS
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myCart),
        centerTitle: true,
        actions: [
          // Delete selected button
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable:
                _cartProvider?.cartItemsNotifier ?? ValueNotifier([]),
            builder: (context, items, _) {
              final hasSelected =
                  _selectedProducts.values.any((selected) => selected);

              if (!hasSelected) return const SizedBox.shrink();

              return IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteSelectedProducts,
                tooltip: l10n.delete,
              );
            },
          ),
        ],
      ),
      body: user == null ? _buildAuthPrompt(l10n) : _buildCartContent(l10n),
      bottomNavigationBar: user != null ? _buildCheckoutButton(l10n) : null,
    );
  }

  Widget _buildCartContent(AppLocalizations l10n) {
    // Safety check: if provider not initialized yet, show loading
    if (_cartProvider == null) {
      return _buildLoadingState();
    }

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _cartProvider!.cartItemsNotifier,
      builder: (context, items, _) {
        // Loading state
        if (_cartProvider!.isLoading && items.isEmpty) {
          return _buildLoadingState();
        }

        // Empty cart
        if (items.isEmpty) {
          return _buildEmptyCart(l10n);
        }

        // Update selections for new items
        _syncSelections(items);

        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;

        // Build cart list
        return RefreshIndicator(
          onRefresh: _handleRefresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Cart items - Grid for tablet, List for mobile
              if (isTablet)
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 200,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        return _buildCartItem(item);
                      },
                      childCount: items.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];

                        // ✅ Calculate seller header dynamically for reliability
                        final currentSellerId = item['sellerId'] as String? ?? '';
                        final showSellerHeader = index == 0 ||
                            currentSellerId != (items[index - 1]['sellerId'] as String? ?? '');

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showSellerHeader) _buildSellerHeader(item),
                            _buildCartItem(item),
                          ],
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                ),

              // ✅ ADD: Loading indicator when loading more
              if (_cartProvider!.isLoading && items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.loading ?? 'Loading more...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _syncSelections(List<Map<String, dynamic>> items) {
    final currentProductIds = items
        .where((item) => item['product'] != null)
        .map((item) => (item['product'] as Product).id)
        .toSet();

    // Remove old selections
    _selectedProducts.removeWhere((id, _) => !currentProductIds.contains(id));

    // Add new items (selected by default)
    for (final productId in currentProductIds) {
      _selectedProducts.putIfAbsent(productId, () => true);
    }
  }

  Widget _buildSellerHeader(Map<String, dynamic> item) {
    final sellerName = item['sellerName'] as String? ?? 'Unknown';
    final isShop = item['isShop'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isShop ? Icons.store : Icons.person,
            size: 18,
            color: Colors.orange,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              sellerName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {
    final product = item['product'] as Product?;

    if (product == null) {
      return const ProductCardShimmer(
        portraitImageHeight: 80,
      );
    }

    final isSelected = _selectedProducts[product.id] ?? true;
    final quantity = item['quantity'] as int? ?? 1;
    final cartData = item['cartData'] as Map<String, dynamic>;
    final selectedColor = cartData['selectedColor'] as String?;

    // Calculate available stock
    int availableStock;
    if (selectedColor != null &&
        product.colorQuantities.containsKey(selectedColor)) {
      availableStock = product.colorQuantities[selectedColor] ?? 0;
    } else {
      availableStock = product.quantity;
    }

    final salePrefs = item['salePreferences'] as Map<String, dynamic>?;
    final maxAllowed = salePrefs?['maxQuantity'] as int?;
    final maxQuantity = maxAllowed != null
        ? math.min(maxAllowed, availableStock)
        : availableStock;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.orange : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 1 : 1,
        ),
      ),
      child: Column(
        children: [
          // Product info
          InkWell(
            onTap: () {
              setState(() {
                _selectedProducts[product.id] = !isSelected;                
              });
              _updateTotalsForCurrentSelection();
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          _selectedProducts[product.id] = value ?? false;
                        });
                        _updateTotalsForCurrentSelection();
                      },
                      activeColor: Colors.orange,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Product image - FIX: Use CachedNetworkImage for instant loading
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl:
                          item['selectedColorImage'] ?? product.imageUrls.first,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey[200],
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.grey),
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey[300],
                        child: const Icon(Icons.image_not_supported, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Product details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${product.price.toStringAsFixed(2)} ${product.currency}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.orange,
                          ),
                        ),
                        if (availableStock < 10)
                          Text(
                            AppLocalizations.of(context)
                                .onlyLeft(availableStock),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _removeItem(product.id),
                    color: Colors.red,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

          // Quantity controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${AppLocalizations.of(context).quantity}:',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: quantity > 1
                          ? () => _updateQuantity(product.id, quantity - 1)
                          : null,
                      color: Colors.orange,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        quantity.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: quantity < maxQuantity
                          ? () => _updateQuantity(product.id, quantity + 1)
                          : null,
                      color: Colors.orange,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Sale preference label
          if (salePrefs != null) _buildSalePreferenceLabel(quantity, salePrefs),
        ],
      ),
    );
  }

  Widget _buildSalePreferenceLabel(
      int quantity, Map<String, dynamic> salePrefs) {
    final l10n = AppLocalizations.of(context);
    final threshold = salePrefs['discountThreshold'] as int?;
    final percentage = salePrefs['bulkDiscountPercentage'] as int?;

    if (threshold == null || percentage == null) {
      return const SizedBox.shrink();
    }

    final hasDiscount = quantity >= threshold;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hasDiscount
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDiscount ? Colors.green : Colors.orange,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDiscount ? Icons.check_circle : Icons.local_offer,
            size: 14,
            color: hasDiscount ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasDiscount
                  ? l10n.youGotDiscount(percentage)
                  : l10n.buyForDiscount(threshold, percentage),
              style: TextStyle(
                color: hasDiscount ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildCheckoutButton(AppLocalizations l10n) {
  if (_cartProvider == null) {
    return const SizedBox.shrink();
  }

  return ValueListenableBuilder<List<Map<String, dynamic>>>(
    valueListenable: _cartProvider!.cartItemsNotifier,
    builder: (context, items, _) {
      final selectedIds = _selectedProducts.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList();

      final isDark = Theme.of(context).brightness == Brightness.dark;

      return ValueListenableBuilder<SalesConfig>(
        valueListenable: _salesConfigService.configNotifier,
        builder: (context, salesConfig, _) {
          final isSalesPaused = salesConfig.salesPaused;

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1A29)
                  : Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ ADD: Sales paused banner
                  if (isSalesPaused)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              salesConfig.pauseReason?.isNotEmpty == true
                                  ? salesConfig.pauseReason!
                                  : (l10n.salesTemporarilyPaused ??
                                      'Sales are temporarily paused'),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Total section (unchanged)
                 ValueListenableBuilder<bool>(
  valueListenable: _cartProvider!.isTotalsLoadingNotifier,
  builder: (context, isLoading, _) {
    return ValueListenableBuilder<CartTotals?>(
      valueListenable: _cartProvider!.cartTotalsNotifier,
      builder: (context, totals, _) {
        if (isLoading || (totals == null && selectedIds.isNotEmpty)) {
          return _buildTotalsShimmer(l10n, selectedIds.length);
        }

        if (totals == null || selectedIds.isEmpty) {
          return const SizedBox.shrink();
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.total,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  '${totals.total.toStringAsFixed(2)} ${totals.currency}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            Text(
              '${selectedIds.length} ${l10n.items}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        );
      },
    );
  },
),
                  const SizedBox(height: 16),

                  // Checkout button - now considers sales paused state
                  Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final isTablet = screenWidth >= 600;

                      // Button disabled when sales paused
                      final isDisabled = selectedIds.isEmpty ||
                          _isValidating ||
                          isSalesPaused;

                      final button = SizedBox(
                        width: isTablet ? screenWidth * 0.5 : double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isDisabled ? null : _proceedToCheckout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isSalesPaused ? Colors.grey : Colors.orange,
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                          ),
                          child: _isValidating
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      l10n.validating ?? 'Validating...',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isSalesPaused) ...[
                                      const Icon(
                                        Icons.pause_circle_outline,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Text(
                                      isSalesPaused
                                          ? (l10n.checkoutPaused ??
                                              'Checkout Paused')
                                          : l10n.proceedToPayment,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      );

                      return isTablet ? Center(child: button) : button;
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) => const ProductCardShimmer(
        portraitImageHeight: 80,
      ),
    );
  }

  Widget _buildEmptyCart(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/empty-cart.png',
                width: 130,
                height: 130,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.yourCartIsEmpty,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final marketScreenState =
                      context.findAncestorStateOfType<State<MarketScreen>>()
                          as MarketScreenState?;
                  marketScreenState?.navigateToTab(1);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0)),
                ),
                child: Text(
                  l10n.discover,
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthPrompt(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty-cart.png',
              width: 150,
              height: 150,
              color: isDark ? Colors.white.withValues(alpha: 0.3) : null,
              colorBlendMode: isDark ? BlendMode.srcATop : null,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noLoggedInForCart,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => context.push('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            l10n.login2,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => context.push('/register'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                          ),
                          child: Text(
                            l10n.register,
                            style: GoogleFonts.inter(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
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
    );
  }

}
