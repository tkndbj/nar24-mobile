import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../product_card_4.dart';
import '../../../providers/my_products_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS - Pre-computed colors to avoid withOpacity() calls during build
// ═══════════════════════════════════════════════════════════════════════════

class _AppColors {
  static const Color jadeGreen = Color(0xFF00A86B);
  static const Color jadeGreenLight = Color(0x1A00A86B); // 10%

  // Dark theme colors
  static const Color darkCard = Color.fromARGB(255, 33, 31, 49);
  static const Color darkCardBorder = Color(0x0DFFFFFF); // 5% white
  static const Color darkCardShadow = Color(0x33000000); // 20% black
  static const Color darkOverlay = Color(0x02FFFFFF); // ~1% white
  static const Color darkDivider = Color(0x0DFFFFFF); // 5% white

  // Light theme colors
  static const Color lightCardBorder = Color(0x0F000000); // 6% black
  static const Color lightCardShadow = Color(0x0A000000); // 4% black
  static const Color lightOverlay = Color(0x08808080); // 3% grey
  static const Color lightDivider = Color(0x0D000000); // 5% black

  // Shared
  static const Color searchShadow = Color(0x05000000); // 2% black
}

// ═══════════════════════════════════════════════════════════════════════════
// PRE-BUILT DECORATIONS - Avoid recreating BoxDecoration on every build
// ═══════════════════════════════════════════════════════════════════════════

class _Decorations {
  static final darkCardDecoration = BoxDecoration(
    color: _AppColors.darkCard,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _AppColors.darkCardBorder, width: 1),
    boxShadow: const [
      BoxShadow(
        color: _AppColors.darkCardShadow,
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  static final lightCardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _AppColors.lightCardBorder, width: 1),
    boxShadow: const [
      BoxShadow(
        color: _AppColors.lightCardShadow,
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  static BoxDecoration getCardDecoration(bool isDark) =>
      isDark ? darkCardDecoration : lightCardDecoration;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ListedProductsTab extends StatefulWidget {
  const ListedProductsTab({Key? key}) : super(key: key);

  @override
  State<ListedProductsTab> createState() => _ListedProductsTabState();
}

class _ListedProductsTabState extends State<ListedProductsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  bool _isDisposed = false;

  String? _openOverlayProductId;

  @override
  void dispose() {
    _isDisposed = true;
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final user = _auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return _NotLoggedInPlaceholder(l10n: l10n);
    }

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: Column(
        children: [
          _SearchBox(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            hint: l10n.searchProducts,
          ),
          Expanded(
            child: Stack(
              children: [
                Selector<MyProductsProvider,
                    ({bool isLoading, List<Product> products})>(
                  selector: (_, provider) => (
                    isLoading: provider.isLoading,
                    products: provider.products,
                  ),
                  builder: (context, data, child) {
                    if (data.isLoading) {
                      return const _LoadingIndicator();
                    }

                    if (data.products.isEmpty) {
                      return _NoProductsPlaceholder(
                        l10n: l10n,
                        isDisposed: () => _isDisposed,
                      );
                    }

                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                          sliver: SliverList.builder(
                            itemCount: data.products.length,
                            itemBuilder: (context, index) {
                              final product = data.products[index];
                              return _ProductListItem(
                                key: ValueKey(product.id),
                                product: product,
                                isDark: isDark,
                                isOverlayOpen:
                                    _openOverlayProductId == product.id,
                                onToggleOverlay: () =>
                                    _toggleOverlay(product.id),
                                onDelete: () =>
                                    _showDeleteDialog(context, product),
                                l10n: l10n,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Selector<MyProductsProvider, bool>(
                  selector: (_, provider) => provider.products.isNotEmpty,
                  builder: (context, hasProducts, child) {
                    if (!hasProducts) return const SizedBox.shrink();
                    return child!;
                  },
                  child: _AddProductButton(
                    l10n: l10n,
                    isDisposed: () => _isDisposed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isDisposed) {
        context
            .read<MyProductsProvider>()
            .setSearchQuery(value.trim().toLowerCase());
      }
    });
  }

  void _toggleOverlay(String productId) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _openOverlayProductId =
          _openOverlayProductId == productId ? null : productId;
    });
  }

  void _showDeleteDialog(BuildContext context, Product product) {
    if (!mounted || _isDisposed) return;

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          l10n.confirmDeletion,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Figtree',
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.confirmDeletionMessage,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (mounted) Navigator.of(ctx).pop();
            },
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.of(ctx).pop();
              _showDeletingProductModal(l10n, isDark);

              try {
                final functions =
                    FirebaseFunctions.instanceFor(region: 'europe-west3');
                await functions.httpsCallable('deleteProduct').call({
                  'productId': product.id,
                });

                if (mounted && !_isDisposed) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l10n.productDeletedSuccessfully),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF00A86B),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              } on FirebaseFunctionsException catch (e) {
                if (mounted && !_isDisposed) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child:
                                Text(e.message ?? l10n.failedToDeleteProduct),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Delete error: $e');
                if (mounted && !_isDisposed) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l10n.failedToDeleteProduct),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              l10n.confirm,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletingProductModal(AppLocalizations l10n, bool isDark) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.deletingProduct,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFamily: 'Figtree',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.deletingProductDesc,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  fontFamily: 'Figtree',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 8,
                  width: double.infinity,
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(seconds: 2),
                    builder: (context, value, child) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.transparent,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.red),
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
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXTRACTED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String hint;

  const _SearchBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? _AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isDark ? _AppColors.darkCardBorder : _AppColors.lightCardBorder,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: _AppColors.searchShadow,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 15,
            fontFamily: 'Figtree',
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 15,
              fontFamily: 'Figtree',
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: _AppColors.jadeGreen,
        strokeWidth: 2.5,
      ),
    );
  }
}

class _ProductListItem extends StatefulWidget {
  final Product product;
  final bool isDark;
  final bool isOverlayOpen;
  final VoidCallback onToggleOverlay;
  final VoidCallback onDelete;
  final AppLocalizations l10n;

  const _ProductListItem({
    super.key,
    required this.product,
    required this.isDark,
    required this.isOverlayOpen,
    required this.onToggleOverlay,
    required this.onDelete,
    required this.l10n,
  });

  @override
  State<_ProductListItem> createState() => _ProductListItemState();
}

class _ProductListItemState extends State<_ProductListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _overlayController;
  late final Animation<Offset> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _overlayAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(_ProductListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOverlayOpen && !oldWidget.isOverlayOpen) {
      _overlayController.forward();
    } else if (!widget.isOverlayOpen && oldWidget.isOverlayOpen) {
      _overlayController.reverse();
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isBoosted = product.isBoosted == true && product.boostEndTime != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _Decorations.getCardDecoration(widget.isDark),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/product/${product.id}'),
                    child: ProductCard4(
                      key: ValueKey('card_${product.id}'),
                      imageUrl: product.imageUrls.isNotEmpty
                          ? product.imageUrls[0]
                          : '',
                      colorImages: product.colorImages ?? {},
                      brandModel: product.brandModel ?? '',
                      productName: product.productName,
                      price: product.price,
                      currency: product.currency,
                      averageRating: product.averageRating ?? 0.0,
                      scaleFactor: 1.0,
                      showOverlayIcons: false,
                      productId: product.id,
                    ),
                  ),
                  _ActionButtonsBar(
                    product: product,
                    isDark: widget.isDark,
                    isBoosted: isBoosted,
                    onStatsPressed: widget.onToggleOverlay,
                    onDeletePressed: widget.onDelete,
                    l10n: widget.l10n,
                  ),
                ],
              ),
              if (isBoosted)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _BoostLabel(
                    endTime: product.boostEndTime!.toDate(),
                    l10n: widget.l10n,
                  ),
                ),
              if (widget.isOverlayOpen)
                Positioned.fill(
                  child: _StatsOverlay(
                    product: product,
                    isDark: widget.isDark,
                    animation: _overlayAnimation,
                    onClose: widget.onToggleOverlay,
                    l10n: widget.l10n,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsBar extends StatelessWidget {
  final Product product;
  final bool isDark;
  final bool isBoosted;
  final VoidCallback onStatsPressed;
  final VoidCallback onDeletePressed;
  final AppLocalizations l10n;

  const _ActionButtonsBar({
    required this.product,
    required this.isDark,
    required this.isBoosted,
    required this.onStatsPressed,
    required this.onDeletePressed,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? _AppColors.darkOverlay : _AppColors.lightOverlay,
        border: Border(
          top: BorderSide(
            color: isDark ? _AppColors.darkDivider : _AppColors.lightDivider,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.bar_chart_rounded,
            label: l10n.stats,
            onTap: onStatsPressed,
            isDark: isDark,
          ),
          _ActionButton(
            icon: Icons.edit_rounded,
            label: l10n.edit,
            onTap: () => context.push('/edit-product', extra: product),
            isDark: isDark,
          ),
          _ActionButton(
            icon: Icons.local_fire_department_rounded,
            label: isBoosted ? '' : l10n.boostProduct,
            onTap: isBoosted
                ? null
                : () => context.push('/boost-product/${product.id}'),
            isDark: isDark,
            color: isBoosted ? Colors.orange : _AppColors.jadeGreen,
          ),
          _ActionButton(
            icon: Icons.delete_outline_rounded,
            label: l10n.delete,
            onTap: onDeletePressed,
            isDark: isDark,
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDark;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final buttonColor = color ?? (isDark ? Colors.white70 : Colors.black54);
    final effectiveColor =
        isDisabled ? buttonColor.withOpacity(0.5) : buttonColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: effectiveColor, size: 22),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Figtree',
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoostLabel extends StatefulWidget {
  final DateTime endTime;
  final AppLocalizations l10n;

  const _BoostLabel({
    required this.endTime,
    required this.l10n,
  });

  @override
  State<_BoostLabel> createState() => _BoostLabelState();
}

class _BoostLabelState extends State<_BoostLabel> {
  late Duration _remaining;
  Timer? _timer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _computeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isDisposed && mounted) _computeRemaining();
    });
  }

  void _computeRemaining() {
    final newRemaining = widget.endTime.difference(DateTime.now());
    final clamped = newRemaining.isNegative ? Duration.zero : newRemaining;

    if (_isDisposed || !mounted) return;

    setState(() {
      _remaining = clamped;
      if (_remaining == Duration.zero) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) return const SizedBox.shrink();

    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00A86B), Color(0xFF00C878)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D00A86B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$h:$m:$s',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'Figtree',
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  final Product product;
  final bool isDark;
  final Animation<Offset> animation;
  final VoidCallback onClose;
  final AppLocalizations l10n;

  const _StatsOverlay({
    required this.product,
    required this.isDark,
    required this.animation,
    required this.onClose,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SlideTransition(
        position: animation,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? _AppColors.darkCard : Colors.white)
                    .withOpacity(0.98),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(20),
              child: Stack(
                children: [
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatCard(
                          icon: Icons.touch_app_rounded,
                          label: l10n.clickCount,
                          value: '${product.clickCount ?? 0}',
                          isDark: isDark,
                        ),
                        _StatCard(
                          icon: Icons.shopping_cart_rounded,
                          label: l10n.cartCount,
                          value: '${product.cartCount ?? 0}',
                          isDark: isDark,
                        ),
                        _StatCard(
                          icon: Icons.favorite_rounded,
                          label: l10n.favoritesCount,
                          value: '${product.favoritesCount ?? 0}',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onClose,
                        borderRadius: BorderRadius.circular(20),
                        splashColor: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.1),
                        highlightColor: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.05),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? _AppColors.darkOverlay : _AppColors.lightOverlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isDark ? _AppColors.darkCardBorder : _AppColors.lightCardBorder,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _AppColors.jadeGreenLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: _AppColors.jadeGreen),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.bold,
                color: _AppColors.jadeGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotLoggedInPlaceholder extends StatelessWidget {
  final AppLocalizations l10n;

  const _NotLoggedInPlaceholder({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF00A86B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 80,
                color: Color(0xFF00A86B),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.youNeedToLoginToTrackYourProducts,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 240,
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: ElevatedButton(
                onPressed: () => context.push('/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A86B),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(240, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.login_rounded, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      l10n.loginButton,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Figtree',
                        letterSpacing: -0.2,
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

class _NoProductsPlaceholder extends StatelessWidget {
  final AppLocalizations l10n;
  final bool Function() isDisposed;

  const _NoProductsPlaceholder({
    required this.l10n,
    required this.isDisposed,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A86B).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 80,
                      color: Color(0xFF00A86B),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.noProductsOnVitrin,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Figtree',
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.listedProductsEmptyText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Figtree',
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 240,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: ElevatedButton(
                      onPressed: () async {
                        if (isDisposed()) return;

                        try {
                          final userId = FirebaseAuth.instance.currentUser?.uid;
                          if (userId == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.youNeedToLogin),
                                  action: SnackBarAction(
                                    label: l10n.pleaseLogin,
                                    onPressed: () {
                                      if (context.mounted) {
                                        context.push('/login');
                                      }
                                    },
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          final userDoc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(userId)
                              .get();

                          if (isDisposed() || !context.mounted) return;

                          final sellerInfo = userDoc.data()?['sellerInfo']
                              as Map<String, dynamic>?;
                          if (sellerInfo != null) {
                            context.push('/list_product_screen');
                          } else {
                            context.push('/seller_info',
                                extra: {'redirectToListProduct': true});
                          }
                        } catch (e) {
                          debugPrint('Error checking seller info: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'An error occurred. Please try again.'),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(240, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            l10n.sellOnVitrin,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Figtree',
                              letterSpacing: -0.2,
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
      ],
    );
  }
}

class _AddProductButton extends StatelessWidget {
  final AppLocalizations l10n;
  final bool Function() isDisposed;

  const _AddProductButton({
    required this.l10n,
    required this.isDisposed,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x20000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.push('/archived-products');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0),
                        ),
                      ),
                      icon: const Icon(Icons.archive_rounded, size: 18),
                      label: Flexible(
                        child: Text(
                          l10n.archivedProducts,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x20000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.push('/vitrin_pending_applications');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0),
                        ),
                      ),
                      icon: const Icon(Icons.description_rounded, size: 18),
                      label: Flexible(
                        child: Text(
                          l10n.productApplications,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x20000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (isDisposed()) return;

                        try {
                          final userId = FirebaseAuth.instance.currentUser?.uid;
                          if (userId == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.youNeedToLogin),
                                  action: SnackBarAction(
                                    label: l10n.pleaseLogin,
                                    onPressed: () {
                                      if (context.mounted) context.push('/login');
                                    },
                                  ),
                                ),
                              );
                            }
                            return;
                          }

                          final userDoc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(userId)
                              .get();

                          if (isDisposed() || !context.mounted) return;

                          final sellerInfo =
                              userDoc.data()?['sellerInfo'] as Map<String, dynamic>?;
                          if (sellerInfo != null) {
                            context.push('/list_product_screen');
                          } else {
                            context.push('/seller_info',
                                extra: {'redirectToListProduct': true});
                          }
                        } catch (e) {
                          debugPrint('Error checking seller info: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('An error occurred. Please try again.'),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(0),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Flexible(
                        child: Text(
                          l10n.listProductButton,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
