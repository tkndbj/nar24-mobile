// lib/screens/market/market_cart_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_cart_provider.dart';

// =============================================================================
// ENTRY POINT
// =============================================================================

class MarketCartScreen extends StatelessWidget {
  const MarketCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MarketCartContent();
  }
}

// =============================================================================
// MAIN CONTENT
// =============================================================================

class _MarketCartContent extends StatefulWidget {
  const _MarketCartContent();

  @override
  State<_MarketCartContent> createState() => _MarketCartContentState();
}

class _MarketCartContentState extends State<_MarketCartContent> {
  bool _showClearConfirm = false;

  Future<void> _handleCheckout(
      BuildContext context, MarketCartProvider cart) async {
    if (cart.items.isEmpty) return;
    if (!context.mounted) return;
    context.push('/market-checkout');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Consumer<MarketCartProvider>(
      builder: (context, cart, _) {
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: Text(
              l10n.marketCartTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: const Color(0xFF00A86B),
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: _buildBody(context, isDark, cart),
        );
      },
    );
  }

  Widget _buildBody(
      BuildContext context, bool isDark, MarketCartProvider cart) {
    if (!cart.isInitialized) {
      if (FirebaseAuth.instance.currentUser == null) {
        return _EmptyCart(isDark: isDark);
      }
      return _CartSkeleton(isDark: isDark);
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            if (cart.items.isEmpty) ...[
              SliverFillRemaining(child: _EmptyCart(isDark: isDark)),
            ] else ...[
              // ── Title row ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _TitleRow(
                    isDark: isDark,
                    itemCount: cart.itemCount,
                    onClearAll: () => setState(() => _showClearConfirm = true),
                  ),
                ),
              ),

              // ── Cart items ─────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.only(top: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MarketCartItemCard(
                        item: cart.items[i],
                        isDark: isDark,
                        onQuantityChange: (qty) =>
                            cart.updateQuantity(cart.items[i].itemId, qty),
                        onRemove: () => cart.removeItem(cart.items[i].itemId),
                      ),
                    ),
                    childCount: cart.items.length,
                  ),
                ),
              ),

              // ── Order summary ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _OrderSummary(
                    cart: cart,
                    isDark: isDark,
                    onCheckout: () => _handleCheckout(context, cart),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),

        // ── Clear cart confirmation ──────────────────────────────────
        if (_showClearConfirm)
          _ClearCartDialog(
            isDark: isDark,
            onCancel: () => setState(() => _showClearConfirm = false),
            onConfirm: () {
              context.read<MarketCartProvider>().clearCart();
              setState(() => _showClearConfirm = false);
            },
          ),
      ],
    );
  }
}

// =============================================================================
// TITLE ROW
// =============================================================================

class _TitleRow extends StatelessWidget {
  final bool isDark;
  final int itemCount;
  final VoidCallback onClearAll;

  const _TitleRow({
    required this.isDark,
    required this.itemCount,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Text(
          l10n.marketCartTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? Colors.green.withOpacity(0.15) : Colors.green[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            l10n.marketCartItemCount(itemCount),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.green[400] : Colors.green[600],
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onClearAll,
          child: Text(
            l10n.marketCartClear,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.red[400] : Colors.red[500],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// CART ITEM CARD
// =============================================================================

class _MarketCartItemCard extends StatelessWidget {
  final MarketCartItem item;
  final bool isDark;
  final ValueChanged<int> onQuantityChange;
  final VoidCallback onRemove;

  const _MarketCartItemCard({
    required this.item,
    required this.isDark,
    required this.onQuantityChange,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final category = kMarketCategoryMap[item.category];

    return AnimatedOpacity(
      opacity: item.isOptimistic ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Thumbnail ──────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: item.imageUrl.isNotEmpty
                      ? Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _Placeholder(category: category, isDark: isDark),
                        )
                      : _Placeholder(category: category, isDark: isDark),
                ),
              ),
              const SizedBox(width: 12),

              // ── Details ────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Brand
                              if (item.brand.isNotEmpty)
                                Text(
                                  item.brand,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[700],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              // Name
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  height: 1.3,
                                  color:
                                      isDark ? Colors.white : Colors.grey[900],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              // Type
                              if (item.type.isNotEmpty)
                                Text(
                                  item.type,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Delete button
                        GestureDetector(
                          onTap: item.isOptimistic ? null : onRemove,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color:
                                  isDark ? Colors.grey[600] : Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Price
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Text(
                            '${item.lineTotal.toStringAsFixed(2)} TL',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          if (item.quantity > 1) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${item.price.toStringAsFixed(2)} × ${item.quantity})',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Quantity controls
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _QuantitySelector(
                        quantity: item.quantity,
                        isDark: isDark,
                        disabled: item.isOptimistic,
                        onDecrease: () => onQuantityChange(item.quantity - 1),
                        onIncrease: () => onQuantityChange(item.quantity + 1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Placeholder thumbnail ────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final MarketCategory? category;
  final bool isDark;

  const _Placeholder({required this.category, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: category != null
            ? category!.color.withOpacity(isDark ? 0.15 : 0.1)
            : (isDark ? const Color(0xFF3A3850) : Colors.grey[100]),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        category?.emoji ?? '📦',
        style: const TextStyle(fontSize: 28),
      ),
    );
  }
}

// =============================================================================
// QUANTITY SELECTOR
// =============================================================================

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final bool isDark;
  final bool disabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _QuantitySelector({
    required this.quantity,
    required this.isDark,
    required this.disabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3850) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyBtn(
            icon: Icons.remove_rounded,
            isDark: isDark,
            onTap: (quantity <= 1 || disabled) ? null : onDecrease,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
          ),
          _QtyBtn(
            icon: Icons.add_rounded,
            isDark: isDark,
            onTap: disabled ? null : onIncrease,
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback? onTap;

  const _QtyBtn({required this.icon, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null
              ? (isDark ? Colors.grey[600] : Colors.grey[400])
              : (isDark ? Colors.grey[400] : Colors.grey[700]),
        ),
      ),
    );
  }
}

// =============================================================================
// ORDER SUMMARY
// =============================================================================

class _OrderSummary extends StatelessWidget {
  final MarketCartProvider cart;
  final bool isDark;
  final VoidCallback onCheckout;

  const _OrderSummary({
    required this.cart,
    required this.isDark,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final totals = cart.totals;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.marketCartOrderSummary,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 16),

            // Item breakdown
            ...cart.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      '${item.quantity}×',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${item.lineTotal.toStringAsFixed(2)} TL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              );
            }),

            Divider(
              color: isDark ? const Color(0xFF3A3850) : const Color(0xFFD1D5DB),
              height: 24,
            ),

            // Total
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.marketCartTotalLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.grey[600] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: '${totals.subtotal.toStringAsFixed(2)} ',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00A86B),
                        ),
                        children: const [
                          TextSpan(
                            text: 'TL',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  l10n.marketCartDeliveryFeeWillBeCalculated,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Checkout button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: cart.items.isEmpty ? null : onCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A86B),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0),
                  ),
                ),
                child: Text(
                  l10n.marketCartProceedToCheckout,
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
    );
  }
}

// =============================================================================
// CLEAR CART DIALOG
// =============================================================================

class _ClearCartDialog extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ClearCartDialog({
    required this.isDark,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onCancel,
      child: Container(
        color: Colors.black.withOpacity(0.4),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF211F31) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF2D2B3F) : const Color(0xFFD1D5DB),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.red.withOpacity(0.15)
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_rounded,
                            size: 20, color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.marketCartClearDialogTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.marketCartClearDialogBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF211F31) : Colors.grey[50],
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? const Color(0xFF2D2B3F)
                            : Colors.grey[300]!,
                      ),
                    ),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF2D2B3F)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              l10n.marketCartClearDialogCancel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: onConfirm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red[500],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              l10n.marketCartClear,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
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
  }
}

// =============================================================================
// EMPTY CART
// =============================================================================

class _EmptyCart extends StatelessWidget {
  final bool isDark;

  const _EmptyCart({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2D2B3F) : Colors.green[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 40,
                color: isDark ? Colors.grey[600] : Colors.green[300],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.marketCartEmptyTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.marketCartEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SKELETON
// =============================================================================

class _CartSkeleton extends StatelessWidget {
  final bool isDark;
  const _CartSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF3A3850) : Colors.grey[200]!;
    final card = isDark ? const Color(0xFF2D2B3F) : Colors.white;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 20),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Container(height: 22, width: 80, color: bg),
            const SizedBox(width: 10),
            Container(
              height: 18,
              width: 50,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const Spacer(),
            Container(height: 18, width: 50, color: bg),
          ]),
        ),
        const SizedBox(height: 12),

        // Item skeletons
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: card,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 10, width: 50, color: bg),
                        const SizedBox(height: 6),
                        Container(height: 14, width: 140, color: bg),
                        const SizedBox(height: 6),
                        Container(height: 11, width: 80, color: bg),
                        const SizedBox(height: 10),
                        Container(height: 14, width: 70, color: bg),
                        const SizedBox(height: 10),
                        Container(
                          height: 32,
                          width: 96,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
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

        // Summary skeleton
        Container(
          padding: const EdgeInsets.all(16),
          color: card,
          child: Column(children: [
            Container(height: 14, width: 100, color: bg),
            const SizedBox(height: 16),
            ...List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(height: 11, width: 120, color: bg),
                  const Spacer(),
                  Container(height: 11, width: 56, color: bg),
                ]),
              ),
            ),
            Divider(
                color:
                    isDark ? const Color(0xFF3A3850) : const Color(0xFFD1D5DB),
                height: 24),
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 10, width: 40, color: bg),
                const SizedBox(height: 6),
                Container(height: 24, width: 100, color: bg),
              ]),
              const Spacer(),
              Container(height: 11, width: 140, color: bg),
            ]),
            const SizedBox(height: 20),
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
