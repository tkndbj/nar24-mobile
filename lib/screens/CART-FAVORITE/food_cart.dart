// lib/screens/food/food_cart_screen.dart
//
// Mirrors: app/food-cart/page.tsx + FoodCartPageContent + FoodCartItemCard

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/foodData.dart';
import '../../constants/foodExtras.dart';
import '../../models/food.dart';
import '../../providers/food_cart_provider.dart';

// ─── Route ────────────────────────────────────────────────────────────────────
// GoRoute(
//   path: '/food-cart',
//   name: 'food-cart',
//   builder: (_, __) => const FoodCartScreen(),
// )

// =============================================================================
// ENTRY POINT
// In Flutter the FoodCartProvider is already in the tree (main.dart / shell).
// This screen consumes it directly — no wrapper needed.
// =============================================================================

class FoodCartScreen extends StatelessWidget {
  const FoodCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FoodCartContent();
  }
}

// =============================================================================
// MAIN CONTENT  —  mirrors FoodCartPageContent
// =============================================================================

class _FoodCartContent extends StatefulWidget {
  const _FoodCartContent();

  @override
  State<_FoodCartContent> createState() => _FoodCartContentState();
}

class _FoodCartContentState extends State<_FoodCartContent> {
  // ── Editing extras state — mirrors editingItem ────────────────────────────
  FoodCartItem? _editingItem;

  // ── Clear cart confirmation — mirrors showClearConfirm ────────────────────
  bool _showClearConfirm = false;

  // ── estimatedPrepTime — Math.max across all items' preparationTime ────────
  int _estimatedPrepTime(List<FoodCartItem> items) {
    if (items.isEmpty) return 0;
    return items.fold<int>(
        0,
        (max, i) =>
            (i.preparationTime ?? 0) > max ? (i.preparationTime ?? 0) : max);
  }

  // ── handleCheckout — mirrors handleCheckout ───────────────────────────────
  void _handleCheckout(BuildContext context, FoodCartProvider cart) {
    if (cart.items.isEmpty) return;
    // Mirrors sessionStorage.setItem('foodCheckoutData', ...) then push('/food-checkout')
    // In Flutter we pass cart state via GoRouter extra or read it from the provider.
    context.push('/food-checkout');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<FoodCartProvider>(
      builder: (context, cart, _) {
        final prepTime = _estimatedPrepTime(cart.items);

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF030712) : const Color(0xFFE5E7EB),
          appBar: AppBar(
            backgroundColor:
                isDark ? const Color(0xFF030712) : const Color(0xFFE5E7EB),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[700]),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: _buildBody(context, isDark, cart, prepTime),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    FoodCartProvider cart,
    int prepTime,
  ) {
    // ── Not initialized (loading) — mirrors !isInitialized skeleton ───────
    if (!cart.isInitialized) {
      // Unauthenticated users will never initialize; show empty cart directly.
      if (FirebaseAuth.instance.currentUser == null) {
        return _EmptyCart(isDark: isDark);
      }
      return _FoodCartSkeleton(isDark: isDark);
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── Empty cart ───────────────────────────────────────────────
            if (cart.items.isEmpty) ...[
              SliverFillRemaining(
                child: _EmptyCart(isDark: isDark),
              ),
            ] else ...[
              // ── Title row ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                  child: _TitleRow(
                    isDark: isDark,
                    itemCount: cart.itemCount,
                    onClearAll: () => setState(() => _showClearConfirm = true),
                  ),
                ),
              ),

              // ── Restaurant header card ────────────────────────────────
              if (cart.currentRestaurant != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                    child: _RestaurantHeaderCard(
                      restaurant: cart.currentRestaurant!,
                      prepTime: prepTime,
                      isDark: isDark,
                      onTap: () => context.push(
                          '/restaurant-detail/${cart.currentRestaurant!.id}'),
                    ),
                  ),
                ),

              // ── Cart items ────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _FoodCartItemCard(
                        item: cart.items[i],
                        isDark: isDark,
                        onQuantityChange: (qty) =>
                            cart.updateQuantity(cart.items[i].foodId, qty),
                        onRemove: () => cart.removeItem(cart.items[i].foodId),
                        onEditExtras: () =>
                            setState(() => _editingItem = cart.items[i]),
                      ),
                    ),
                    childCount: cart.items.length,
                  ),
                ),
              ),

              // ── Order summary ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
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

        // ── Edit Extras Sheet ────────────────────────────────────────────
        if (_editingItem != null)
          _FoodExtrasSheetModal(
            item: _editingItem!,
            isDark: isDark,
            onClose: () => setState(() => _editingItem = null),
            onConfirm: (extras, notes, qty) async {
              final cart = context.read<FoodCartProvider>();
              await cart.updateExtras(_editingItem!.foodId, extras);
              await cart.updateNotes(_editingItem!.foodId, notes);
              await cart.updateQuantity(_editingItem!.foodId, qty);
              setState(() => _editingItem = null);
            },
          ),

        // ── Clear cart confirmation ───────────────────────────────────────
        if (_showClearConfirm)
          _ClearCartDialog(
            isDark: isDark,
            onCancel: () => setState(() => _showClearConfirm = false),
            onConfirm: () {
              context.read<FoodCartProvider>().clearCart();
              setState(() => _showClearConfirm = false);
            },
          ),
      ],
    );
  }
}

// =============================================================================
// BACK BUTTON  —  mirrors the ArrowLeft button
// =============================================================================

class _BackButton extends StatelessWidget {
  final bool isDark;
  const _BackButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          size: 16,
          color: isDark ? Colors.grey[400] : Colors.grey[500],
        ),
      ),
    );
  }
}

// =============================================================================
// TITLE ROW  —  mirrors title + item count badge + Clear All
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
    return Row(
      children: [
        // Title
        Text(
          'Food Cart',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
        const SizedBox(width: 10),

        // Item count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isDark ? Colors.orange.withOpacity(0.15) : Colors.orange[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.orange[400] : Colors.orange[600],
            ),
          ),
        ),

        const Spacer(),

        // Clear all button
        GestureDetector(
          onTap: onClearAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Clear All',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.red[400] : Colors.red[500],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// RESTAURANT HEADER CARD  —  mirrors the currentRestaurant card
// =============================================================================

class _RestaurantHeaderCard extends StatelessWidget {
  final FoodCartRestaurant restaurant;
  final int prepTime;
  final bool isDark;
  final VoidCallback onTap;

  const _RestaurantHeaderCard({
    required this.restaurant,
    required this.prepTime,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB),
        ),
      ),
      child: Column(
        children: [
          // ── Restaurant info row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Profile image / ChefHat icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withOpacity(0.15)
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: restaurant.profileImageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            restaurant.profileImageUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _ChefIcon(isDark: isDark),
                          ),
                        )
                      : _ChefIcon(isDark: isDark),
                ),
                const SizedBox(width: 12),

                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ordering from this restaurant',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // ChevronRight — navigates to restaurant detail
                GestureDetector(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Prep time indicator ─────────────────────────────────────
          if (prepTime > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.grey[800]!.withOpacity(0.4)
                    : Colors.grey[50]!.withOpacity(0.6),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(
                      text: 'Estimated preparation: ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      children: [
                        TextSpan(
                          text: '~$prepTime min',
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[600],
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
    );
  }
}

class _ChefIcon extends StatelessWidget {
  final bool isDark;
  const _ChefIcon({required this.isDark});

  @override
  Widget build(BuildContext context) => Icon(
        Icons.restaurant_rounded,
        size: 20,
        color: isDark ? Colors.orange[400] : Colors.orange[500],
      );
}

// =============================================================================
// FOOD CART ITEM CARD  —  mirrors FoodCartItemCard component
// =============================================================================

class _FoodCartItemCard extends StatelessWidget {
  final FoodCartItem item;
  final bool isDark;
  final ValueChanged<int> onQuantityChange;
  final VoidCallback onRemove;
  final VoidCallback onEditExtras;

  const _FoodCartItemCard({
    required this.item,
    required this.isDark,
    required this.onQuantityChange,
    required this.onRemove,
    required this.onEditExtras,
  });

  double get _extrasTotal =>
      item.extras.fold(0.0, (s, e) => s + e.price * e.quantity);

  double get _lineTotal => (item.price + _extrasTotal) * item.quantity;

  /// Mirrors getExtraName — looks up translation key then falls back to name
  /// TODO: wire up AppLocalizations
  String _extraName(String name) {
    // final key = FoodExtrasData.kExtrasTranslationKeys[name];
    // if (key == null) return name;
    // return AppLocalizations.of(context)!.translate(key);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: (item.isOptimistic) ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Food image or category icon ──────────────────────
                  _ItemThumbnail(item: item, isDark: isDark),
                  const SizedBox(width: 12),

                  // ── Details ──────────────────────────────────────────
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
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.grey[900],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.foodType,
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

                            // Trash button
                            GestureDetector(
                              onTap: item.isOptimistic ? null : onRemove,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Price line
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Text(
                                '${_lineTotal.toStringAsFixed(2)} TL',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
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

                        // Quantity controls + Edit button
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              // Quantity selector
                              _QuantitySelector(
                                quantity: item.quantity,
                                isDark: isDark,
                                disabled: item.isOptimistic,
                                onDecrease: () =>
                                    onQuantityChange(item.quantity - 1),
                                onIncrease: () =>
                                    onQuantityChange(item.quantity + 1),
                              ),

                              const Spacer(),

                              // Edit button
                              GestureDetector(
                                onTap: onEditExtras,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_rounded,
                                        size: 11,
                                        color: isDark
                                            ? Colors.orange[400]
                                            : Colors.orange[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Edit',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.orange[400]
                                              : Colors.orange[600],
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
                ],
              ),

              // ── Extras pills ────────────────────────────────────────
              if (item.extras.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: item.extras.map((ext) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1F2937)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('+',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.orange)),
                            const SizedBox(width: 2),
                            Text(
                              _extraName(ext.name),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                            ),
                            if (ext.quantity > 1) ...[
                              const SizedBox(width: 2),
                              Text(
                                '×${ext.quantity}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // ── Special notes ────────────────────────────────────────
              if (item.specialNotes != null && item.specialNotes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey[800]!.withOpacity(0.6)
                          : Colors.amber[50]!.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 11,
                            color: isDark
                                ? Colors.amber[500]!.withOpacity(0.6)
                                : Colors.amber[400],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.specialNotes!,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[700],
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
    );
  }
}

// ── Item thumbnail — food image or category icon fallback ────────────────────

class _ItemThumbnail extends StatelessWidget {
  final FoodCartItem item;
  final bool isDark;

  const _ItemThumbnail({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final iconFile = FoodCategoryData.kCategoryIcons[item.foodCategory];

    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.network(
            item.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                _CategoryIconBox(iconFile: iconFile, isDark: isDark),
          ),
        ),
      );
    }

    return _CategoryIconBox(iconFile: iconFile, isDark: isDark);
  }
}

class _CategoryIconBox extends StatelessWidget {
  final String? iconFile;
  final bool isDark;

  const _CategoryIconBox({required this.iconFile, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: iconFile != null
          ? Image.asset(
              'assets/images/foods/$iconFile',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.no_food_rounded,
                size: 24,
                color: isDark ? Colors.grey[600] : Colors.orange[300],
              ),
            )
          : Icon(
              Icons.no_food_rounded,
              size: 24,
              color: isDark ? Colors.grey[600] : Colors.orange[300],
            ),
    );
  }
}

// =============================================================================
// QUANTITY SELECTOR  —  mirrors the − qty + inline control
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
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus
          _QtyBtn(
            icon: Icons.remove_rounded,
            isDark: isDark,
            onTap: (quantity <= 1 || disabled) ? null : onDecrease,
          ),

          // Count
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

          // Plus
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
// ORDER SUMMARY  —  mirrors the Order Summary card
// =============================================================================

class _OrderSummary extends StatelessWidget {
  final FoodCartProvider cart;
  final bool isDark;
  final VoidCallback onCheckout;

  const _OrderSummary({
    required this.cart,
    required this.isDark,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heading
            Text(
              'Order Summary',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 16),

            // Item breakdown
            ...cart.items.map((item) {
              final extrasTotal = item.extras
                  .fold<double>(0, (s, e) => s + e.price * e.quantity);
              final lineTotal = (item.price + extrasTotal) * item.quantity;
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
                      '${lineTotal.toStringAsFixed(2)} ${cart.totals.currency}',
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

            // Divider
            Divider(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB),
              height: 24,
            ),

            // Total row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL',
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
                        text: '${cart.totals.subtotal.toStringAsFixed(2)} ',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                        children: [
                          TextSpan(
                            text: cart.totals.currency,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Delivery fee at checkout',
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
              child: ElevatedButton(
                onPressed: cart.items.isEmpty ? null : onCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.orange.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Proceed to Checkout',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, size: 18),
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

// =============================================================================
// FOOD EXTRAS SHEET MODAL  —  mirrors the FoodExtrasSheet used for editing
// Opens as a bottom sheet overlay; reuses logic from restaurant_detail_screen.
// =============================================================================

class _FoodExtrasSheetModal extends StatefulWidget {
  final FoodCartItem item;
  final bool isDark;
  final VoidCallback onClose;
  final Future<void> Function(
      List<SelectedExtra> extras, String notes, int quantity) onConfirm;

  const _FoodExtrasSheetModal({
    required this.item,
    required this.isDark,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  State<_FoodExtrasSheetModal> createState() => _FoodExtrasSheetModalState();
}

class _FoodExtrasSheetModalState extends State<_FoodExtrasSheetModal> {
  late int _quantity;
  late Map<String, bool> _checked;
  late final TextEditingController _notesController;
  bool _submitting = false;

  // Mirrors: initialExtras, initialNotes, initialQuantity props
  late final List<String> _resolvedExtras;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity;
    _checked = {
      for (final e in widget.item.extras) e.name: true,
    };
    _notesController =
        TextEditingController(text: widget.item.specialNotes ?? '');

    _resolvedExtras = FoodExtrasData.resolveExtras(
      category: widget.item.foodCategory,
      allowedExtras: widget.item.extras.map((e) => e.name).toList(),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final extras = _checked.entries.where((e) => e.value).map((e) {
      // Preserve original price/quantity from existing extras
      final orig = widget.item.extras.where((x) => x.name == e.key).firstOrNull;
      return SelectedExtra(
          name: e.key, quantity: orig?.quantity ?? 1, price: orig?.price ?? 0);
    }).toList();
    try {
      await widget.onConfirm(extras, _notesController.text.trim(), _quantity);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final total = widget.item.price * _quantity;

    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black54,
        child: GestureDetector(
          onTap: () {}, // absorb taps inside sheet
          child: DraggableScrollableSheet(
            initialChildSize: _resolvedExtras.isNotEmpty ? 0.65 : 0.5,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (_, sc) => Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        // Food name + price
                        Row(
                          children: [
                            Expanded(
                              child: Text(widget.item.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Text(
                              '${widget.item.price.toStringAsFixed(0)} TL',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.orange[400]
                                      : Colors.orange[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quantity
                        Row(
                          children: [
                            Text('Quantity',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[800])),
                            const Spacer(),
                            _InlineQtyPicker(
                              value: _quantity,
                              isDark: isDark,
                              onChanged: (v) => setState(() => _quantity = v),
                            ),
                          ],
                        ),

                        // Extras
                        if (_resolvedExtras.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Extras',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[800])),
                          const SizedBox(height: 8),
                          ..._resolvedExtras.map(
                            (extra) => CheckboxListTile(
                              value: _checked[extra] ?? false,
                              onChanged: (v) =>
                                  setState(() => _checked[extra] = v!),
                              title: Text(extra,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.grey[200]
                                          : Colors.grey[900])),
                              subtitle: const Text('Free',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                              activeColor: Colors.orange,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.trailing,
                            ),
                          ),
                        ],

                        // Notes
                        const SizedBox(height: 16),
                        Text('Special notes (optional)',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[800])),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'E.g. no onions…',
                            filled: true,
                            fillColor:
                                isDark ? Colors.grey[800] : Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.grey[600]!
                                    : Colors.grey[400]!,
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Colors.orange,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Confirm button
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20,
                        MediaQuery.of(context).viewInsets.bottom + 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Text('Update — ${total.toStringAsFixed(0)} TL',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
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

class _InlineQtyPicker extends StatelessWidget {
  final int value;
  final bool isDark;
  final ValueChanged<int> onChanged;

  const _InlineQtyPicker(
      {required this.value, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QtyBtn(
            icon: Icons.remove_rounded,
            isDark: isDark,
            onTap: value > 1 ? () => onChanged(value - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$value',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        _QtyBtn(
            icon: Icons.add_rounded,
            isDark: isDark,
            onTap: () => onChanged(value + 1)),
      ],
    );
  }
}

// =============================================================================
// CLEAR CART DIALOG  —  mirrors the showClearConfirm modal
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
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon + text
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
                        'Clear Food Cart?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'This will remove all items from your food cart.',
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

                // Buttons
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey[800]!.withOpacity(0.5)
                        : Colors.grey[50],
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? const Color(0xFF1F2937)
                            : Colors.grey[300]!,
                      ),
                    ),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      // Cancel
                      Expanded(
                        child: GestureDetector(
                          onTap: onCancel,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF374151)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Cancel',
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

                      // Clear
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
                            child: const Text(
                              'Clear Cart',
                              style: TextStyle(
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
// EMPTY CART  —  mirrors the items.length === 0 state
// =============================================================================

class _EmptyCart extends StatelessWidget {
  final bool isDark;

  const _EmptyCart({required this.isDark});

  @override
  Widget build(BuildContext context) {
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
                color: isDark ? const Color(0xFF1F2937) : Colors.orange[50],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.no_food_rounded,
                size: 40,
                color: isDark ? Colors.grey[600] : Colors.orange[300],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your food cart is empty',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Browse restaurants and add delicious meals to your cart',
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
// FOOD CART SKELETON  —  mirrors FoodCartSkeleton component
// =============================================================================

class _FoodCartSkeleton extends StatelessWidget {
  final bool isDark;
  const _FoodCartSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
    final card = isDark ? const Color(0xFF111827) : Colors.white;
    final cardBorder =
        isDark ? const Color(0xFF1F2937) : const Color(0xFFD1D5DB);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Back button skeleton
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 20),

        // Title row
        Row(children: [
          Container(height: 22, width: 100, color: bg),
          const SizedBox(width: 10),
          Container(
              height: 18,
              width: 56,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(20))),
          const Spacer(),
          Container(height: 18, width: 56, color: bg),
        ]),
        const SizedBox(height: 16),

        // Restaurant card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder)),
          child: Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(height: 14, width: 120, color: bg),
                  const SizedBox(height: 6),
                  Container(height: 11, width: 180, color: bg),
                ])),
            Container(width: 18, height: 18, color: bg),
          ]),
        ),
        const SizedBox(height: 12),

        // Item skeletons
        ...List.generate(
            2,
            (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder)),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Container(
                                            height: 14,
                                            width: double.infinity,
                                            color: bg),
                                        const SizedBox(height: 6),
                                        Container(
                                            height: 11, width: 80, color: bg),
                                      ])),
                                  const SizedBox(width: 8),
                                  Container(width: 24, height: 24, color: bg),
                                ]),
                                const SizedBox(height: 10),
                                Container(height: 14, width: 72, color: bg),
                                const SizedBox(height: 10),
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                          height: 32,
                                          width: 96,
                                          decoration: BoxDecoration(
                                              color: bg,
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      Container(
                                          height: 24, width: 44, color: bg),
                                    ]),
                              ])),
                        ]),
                  ),
                )),

        // Summary skeleton
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder)),
          child: Column(children: [
            Container(height: 14, width: 100, color: bg),
            const SizedBox(height: 16),
            ...List.generate(
                2,
                (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(height: 11, width: 120, color: bg),
                        const Spacer(),
                        Container(height: 11, width: 56, color: bg),
                      ]),
                    )),
            Divider(color: cardBorder, height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 10, width: 36, color: bg),
                const SizedBox(height: 6),
                Container(height: 24, width: 100, color: bg),
              ]),
              Container(height: 11, width: 140, color: bg),
            ]),
            const SizedBox(height: 20),
            Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(12))),
          ]),
        ),
      ],
    );
  }
}
