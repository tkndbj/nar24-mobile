import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../screens/PAYMENT-RECEIPT/product_payment_screen.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../auth_service.dart';
import '../login_modal.dart';
import '../product_option_selector.dart';
import '../../services/sales_config_service.dart';

class ProductDetailButtons extends StatefulWidget {
  final Product product;

  const ProductDetailButtons({Key? key, required this.product})
      : super(key: key);

  @override
  State<ProductDetailButtons> createState() => _ProductDetailButtonsState();
}

class _ProductDetailButtonsState extends State<ProductDetailButtons> {
  bool? _localCartState; // Local state for instant UI update
  bool _isPending = false; // Prevent double-taps
  final SalesConfigService _salesConfigService = SalesConfigService();

  Future<void> _showAuthModal(BuildContext context) async {
    if (!context.mounted) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await showCupertinoModalPopup(
        context: context,
        builder: (_) => LoginPromptModal(authService: authService),
      );
    } catch (e) {
      debugPrint('Error showing auth modal: $e');
    }
  }

  void _showInstantSuccessSnackbar(BuildContext context, bool isAdding) {
    if (!context.mounted) return;

    final localizations = AppLocalizations.of(context);
    final message = isAdding
        ? (localizations.addedToCart ?? 'Added to cart')
        : (localizations.removedFromCart ?? 'Removed from cart');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  bool _shouldShowOptionSelector(Product product) {
    if (product.colorImages.isNotEmpty) return true;
    if (product.subsubcategory.toLowerCase() == 'curtains') return true;
    if ((product.clothingSizes?.length ?? 0) > 1) return true;
    if ((product.pantSizes?.length ?? 0) > 1) return true;
    if ((product.footwearSizes?.length ?? 0) > 1) return true;
    if ((product.jewelryMaterials?.length ?? 0) > 1) return true;

    // Backward compat — old products still in attributes map
    const nonSelectable = {
      'clothingType',
      'clothingTypes',
      'pantFabricType',
      'pantFabricTypes',
      'gender',
      'clothingFit',
      'productType',
      'consoleBrand',
      'curtainMaxWidth',
      'curtainMaxHeight',
    };
    for (final entry in product.attributes.entries) {
      if (nonSelectable.contains(entry.key)) continue;
      final value = entry.value;
      if (value is List && value.length > 1) return true;
      if (value is String && value.split(',').length > 1) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bgColor = theme.brightness == Brightness.light
        ? Colors.white
        : const Color(0xFF1C1A29);

    final isOutOfStock = widget.product.quantity == 0 &&
        widget.product.colorQuantities.entries.every((e) => e.value == 0);
    final hasOptions = _shouldShowOptionSelector(widget.product);

    String deliveryText;
    if (widget.product.deliveryOption == "Fast Delivery") {
      deliveryText = localizations.fastDelivery;
    } else if (widget.product.deliveryOption == "Self Delivery") {
      deliveryText = localizations.selfDelivery;
    } else {
      deliveryText = widget.product.deliveryOption;
    }

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1.0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            // Price & delivery info
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 70, maxWidth: 100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${widget.product.price.toStringAsFixed(2)} ${widget.product.currency}",
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                        fontFamily: 'Figtree',
                      ),
                    ),
                    Text(
                      deliveryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00A36C),
                        fontFamily: 'Figtree',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: Row(
                children: [
                  // ✅ Cart button with TRUE instant feedback
                  Expanded(
                    child: ValueListenableBuilder<Set<String>>(
                      valueListenable:
                          Provider.of<CartProvider>(context, listen: false)
                              .cartProductIdsNotifier,
                      builder: (context, cartIds, child) {
                        // Check actual cart state
                        final actualIsInCart =
                            cartIds.contains(widget.product.id);

                        // Use local state for instant UI, fallback to actual state
                        final isInCart = _localCartState ?? actualIsInCart;

                        // Sync local state with actual state when they match
                        if (_localCartState != null &&
                            _localCartState == actualIsInCart &&
                            !_isPending) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _localCartState = null);
                            }
                          });
                        }

                        return ElevatedButton(
                          onPressed: (isOutOfStock || _isPending)
                              ? null
                              : () async {
                                  final isAdding = !isInCart;

                                  // ✅ STEP 1: Check authentication FIRST (before any UI updates)
                                  if (isAdding) {
                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    if (user == null) {
                                      await _showAuthModal(context);
                                      return;
                                    }
                                  }

                                  // ✅ STEP 2: Handle options modal if needed
                                  Map<String, dynamic>? selections;
                                  if (isAdding && hasOptions) {
                                    selections = await showCupertinoModalPopup<
                                        Map<String, dynamic>?>(
                                      context: context,
                                      builder: (_) => ProductOptionSelector(
                                        product: widget.product,
                                        isBuyNow: false,
                                      ),
                                    );

                                    if (selections == null ||
                                        !context.mounted) {
                                      return; // User cancelled
                                    }
                                  }

                                  // ✅ STEP 3: Apply optimistic UI update
                                  setState(() {
                                    _localCartState = isAdding;
                                    _isPending = true;
                                  });

                                  HapticFeedback.lightImpact();

                                  // ✅ STEP 4: Show success snackbar (user is authenticated at this point)
                                  if (isAdding) {
                                    _showInstantSuccessSnackbar(context, true);
                                  }

                                  try {
                                    final cartProvider =
                                        Provider.of<CartProvider>(
                                      context,
                                      listen: false,
                                    );

                                    if (!context.mounted) return;

                                    // ✅ STEP 5: Execute cart operation
                                    String result;

                                    if (isAdding) {
                                      final qty =
                                          selections?['quantity'] as int? ?? 1;
                                      final selectedColor =
                                          selections?['selectedColor']
                                              as String?;
                                      final attrs = selections != null
                                          ? (Map<String, dynamic>.from(
                                              selections)
                                            ..remove('quantity')
                                            ..remove('selectedColor'))
                                          : null;

                                      result =
                                          await cartProvider.addProductToCart(
                                        widget.product,
                                        quantity: qty,
                                        selectedColor: selectedColor,
                                        attributes: attrs?.isNotEmpty == true
                                            ? attrs
                                            : null,
                                      );
                                    } else {
                                      result = await cartProvider
                                          .removeFromCart(widget.product.id);
                                    }

                                    // ✅ STEP 6: Handle actual errors (not auth - already checked)
                                    if (context.mounted &&
                                        result != 'Added to cart' &&
                                        result != 'Removed from cart' &&
                                        result != 'Operation in progress') {
                                      _showErrorSnackbar(context, result);
                                      setState(() {
                                        _localCartState = null;
                                        _isPending = false;
                                      });
                                    }
                                  } catch (e) {
                                    debugPrint('Cart operation error: $e');
                                    if (context.mounted) {
                                      _showErrorSnackbar(
                                          context, 'Operation failed');
                                    }
                                    setState(() {
                                      _localCartState = null;
                                      _isPending = false;
                                    });
                                  } finally {
                                    if (mounted) {
                                      Future.delayed(
                                          const Duration(milliseconds: 300),
                                          () {
                                        if (mounted) {
                                          setState(() => _isPending = false);
                                        }
                                      });
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            fixedSize: const Size.fromHeight(40),
                            backgroundColor: (isOutOfStock)
                                ? Colors.grey.shade400
                                : (_localCartState != null
                                    ? (_localCartState!
                                        ? Colors.green.shade600
                                        : const Color(
                                            0xFFFF7F50)) // Use local state for color
                                    : (isInCart
                                        ? Colors.green.shade600
                                        : const Color(
                                            0xFFFF7F50))), // Fallback to actual state
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: FittedBox(
                              key: ValueKey('cart-$isInCart'),
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isInCart
                                          ? Icons.check_circle
                                          : Icons.add_shopping_cart,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isOutOfStock
                                          ? localizations.outOfStock
                                          : (isInCart
                                              ? (localizations.inCart ??
                                                  'In Cart')
                                              : localizations.addToCart),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'Figtree',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.white,
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
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: ValueListenableBuilder<SalesConfig>(
                      valueListenable: _salesConfigService.configNotifier,
                      builder: (context, salesConfig, _) {
                        final isSalesPaused = salesConfig.salesPaused;
                        final isDisabled = isOutOfStock || isSalesPaused;

                        return ElevatedButton(
                          onPressed: isDisabled
                              ? null
                              : () async {
                                  try {
                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    if (user == null) {
                                      await _showAuthModal(context);
                                      return;
                                    }

                                    if (!context.mounted) return;

                                    Map<String, dynamic>? selections;
                                    if (hasOptions) {
                                      selections =
                                          await showCupertinoModalPopup<
                                              Map<String, dynamic>?>(
                                        context: context,
                                        builder: (_) => ProductOptionSelector(
                                          product: widget.product,
                                          isBuyNow: true,
                                        ),
                                      );

                                      if (selections == null ||
                                          !context.mounted) return;
                                    } else {
                                      selections = {'quantity': 1};
                                    }

                                    final qty =
                                        selections['quantity'] as int? ?? 1;

                                    // ✅ NEW: Build selectedAttributes map (excluding quantity)
                                    final Map<String, dynamic>
                                        selectedAttributes = {};

                                    selections.forEach((key, value) {
                                      if (key != 'quantity' &&
                                          value != null &&
                                          value != '' &&
                                          (value is! List ||
                                              (value).isNotEmpty)) {
                                        selectedAttributes[key] = value;
                                      }
                                    });

                                    if (!context.mounted) return;

                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProductPaymentScreen(
                                          items: [
                                            {
                                              'product': widget.product,
                                              'quantity': qty,
                                              // ✅ CRITICAL: Wrap in selectedAttributes
                                              if (selectedAttributes.isNotEmpty)
                                                'selectedAttributes':
                                                    selectedAttributes,
                                            }
                                          ],
                                          totalPrice:
                                              widget.product.price * qty,
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    debugPrint('Buy now error: $e');
                                    if (context.mounted) {
                                      _showErrorSnackbar(
                                          context, 'Operation failed');
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            fixedSize: const Size.fromHeight(40),
                            backgroundColor: isOutOfStock
                                ? Colors.grey
                                : (isSalesPaused
                                    ? Colors.grey
                                    : const Color(0xFF00A36C)),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSalesPaused && !isOutOfStock) ...[
                                    const Icon(
                                      Icons.pause_circle_outline,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      isOutOfStock
                                          ? localizations.outOfStock
                                          : (isSalesPaused
                                              ? localizations.checkoutPaused
                                              : localizations.buyItNow),
                                      style: const TextStyle(
                                        fontFamily: 'Figtree',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (!isOutOfStock &&
                                  !isSalesPaused &&
                                  widget.product.quantity > 0 &&
                                  widget.product.quantity <= 10)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        localizations.lastProducts(
                                            widget.product.quantity),
                                        style: const TextStyle(
                                          fontFamily: 'Figtree',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
