import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../constants/foodData.dart';
import '../../utils/food_localization.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class FoodDiscount {
  final int percentage;
  final double originalPrice;
  final Timestamp startDate;
  final Timestamp endDate;

  const FoodDiscount({
    required this.percentage,
    required this.originalPrice,
    required this.startDate,
    required this.endDate,
  });

  factory FoodDiscount.fromMap(Map<String, dynamic> m) => FoodDiscount(
        percentage: (m['percentage'] as num?)?.toInt() ?? 0,
        originalPrice: (m['originalPrice'] as num?)?.toDouble() ?? 0,
        startDate: m['startDate'] as Timestamp,
        endDate: m['endDate'] as Timestamp,
      );

  Map<String, dynamic> toMap() => {
        'percentage': percentage,
        'originalPrice': originalPrice,
        'startDate': startDate,
        'endDate': endDate,
      };

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate.toDate()) && now.isBefore(endDate.toDate());
  }

  bool get isExpired => endDate.toDate().isBefore(DateTime.now());
}

class FoodItem {
  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final double price;
  final String foodCategory;
  final String foodType;
  final String imageUrl;
  final bool isAvailable;
  final int? preparationTime;
  final Timestamp? createdAt;
  final FoodDiscount? discount;

  const FoodItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.foodCategory,
    required this.foodType,
    required this.imageUrl,
    required this.isAvailable,
    this.preparationTime,
    this.createdAt,
    this.discount,
  });

  factory FoodItem.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final discountData = d['discount'] as Map<String, dynamic>?;
    return FoodItem(
      id: doc.id,
      restaurantId: d['restaurantId'] as String? ?? '',
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      price: (d['price'] as num?)?.toDouble() ?? 0,
      foodCategory: d['foodCategory'] as String? ?? '',
      foodType: d['foodType'] as String? ?? '',
      imageUrl: d['imageUrl'] as String? ?? '',
      isAvailable: d['isAvailable'] as bool? ?? true,
      preparationTime: (d['preparationTime'] as num?)?.toInt(),
      createdAt: d['createdAt'] as Timestamp?,
      discount:
          discountData != null ? FoodDiscount.fromMap(discountData) : null,
    );
  }

  FoodItem copyWith({
    double? price,
    bool? isAvailable,
    FoodDiscount? discount,
    bool clearDiscount = false,
  }) =>
      FoodItem(
        id: id,
        restaurantId: restaurantId,
        name: name,
        description: description,
        price: price ?? this.price,
        foodCategory: foodCategory,
        foodType: foodType,
        imageUrl: imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        preparationTime: preparationTime,
        createdAt: createdAt,
        discount: clearDiscount ? null : (discount ?? this.discount),
      );
}

// ─── Constants ────────────────────────────────────────────────────────────────

const _minDiscount = 5;
const _maxDiscount = 90;

// ─── Main Widget ──────────────────────────────────────────────────────────────

class RestaurantFoodsTab extends StatefulWidget {
  final String restaurantId;

  const RestaurantFoodsTab({Key? key, required this.restaurantId})
      : super(key: key);

  @override
  State<RestaurantFoodsTab> createState() => _RestaurantFoodsTabState();
}

class _RestaurantFoodsTabState extends State<RestaurantFoodsTab> {
  final _firestore = FirebaseFirestore.instance;

  List<FoodItem> _foods = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchFoods();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetchFoods() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _firestore
          .collection('foods')
          .where('restaurantId', isEqualTo: widget.restaurantId)
          .orderBy('createdAt', descending: true)
          .get();

      if (!mounted) return;
      setState(() {
        _foods = snap.docs.map(FoodItem.fromDoc).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Toggle Availability ───────────────────────────────────────────────────

  Future<void> _toggleAvailability(FoodItem food) async {
    final newVal = !food.isAvailable;
    // Optimistic update
    setState(() {
      _foods = _foods
          .map((f) => f.id == food.id ? f.copyWith(isAvailable: newVal) : f)
          .toList();
    });
    try {
      await _firestore
          .collection('foods')
          .doc(food.id)
          .update({'isAvailable': newVal});
    } catch (_) {
      // Revert
      if (!mounted) return;
      setState(() {
        _foods = _foods
            .map((f) =>
                f.id == food.id ? f.copyWith(isAvailable: food.isAvailable) : f)
            .toList();
      });
      _showSnackBar(AppLocalizations.of(context).toggleError, isError: true);
    }
  }

  // ── Apply Discount ────────────────────────────────────────────────────────

  Future<void> _applyDiscount(
    FoodItem food,
    int percentage,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final originalPrice = (food.discount != null &&
            (food.discount!.isActive || food.discount!.isExpired))
        ? food.discount!.originalPrice
        : food.price;

    final discountedPrice =
        (originalPrice * (1 - percentage / 100) * 100).roundToDouble() / 100;

    final discountData = FoodDiscount(
      percentage: percentage,
      originalPrice: originalPrice,
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate),
    );

    // Optimistic update
    setState(() {
      _foods = _foods
          .map((f) => f.id == food.id
              ? f.copyWith(price: discountedPrice, discount: discountData)
              : f)
          .toList();
    });

    try {
      await _firestore.collection('foods').doc(food.id).update({
        'price': discountedPrice,
        'discount': discountData.toMap(),
      });
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context).discountApplied,
            isError: false);
      }
    } catch (e) {
      // Revert
      if (!mounted) return;
      setState(() {
        _foods = _foods
            .map((f) => f.id == food.id
                ? f.copyWith(price: food.price, discount: food.discount)
                : f)
            .toList();
      });
      _showSnackBar(AppLocalizations.of(context).discountError, isError: true);
      rethrow;
    }
  }

  // ── Remove Discount ───────────────────────────────────────────────────────

  Future<void> _removeDiscount(FoodItem food) async {
    if (food.discount == null) return;
    final originalPrice = food.discount!.originalPrice;

    // Optimistic update
    setState(() {
      _foods = _foods
          .map((f) => f.id == food.id
              ? f.copyWith(price: originalPrice, clearDiscount: true)
              : f)
          .toList();
    });

    try {
      await _firestore.collection('foods').doc(food.id).update({
        'price': originalPrice,
        'discount': FieldValue.delete(),
      });
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context).discountRemoved,
            isError: false);
      }
    } catch (e) {
      // Revert
      if (!mounted) return;
      setState(() {
        _foods = _foods
            .map((f) => f.id == food.id
                ? f.copyWith(price: food.price, discount: food.discount)
                : f)
            .toList();
      });
      _showSnackBar(AppLocalizations.of(context).discountError, isError: true);
      rethrow;
    }
  }

  // ── Grouped foods by category ─────────────────────────────────────────────

  List<MapEntry<String, List<FoodItem>>> get _foodsByCategory {
    final grouped = <String, List<FoodItem>>{};
    for (final food in _foods) {
      final key = food.foodCategory.isNotEmpty ? food.foodCategory : 'Other';
      grouped.putIfAbsent(key, () => []).add(food);
    }

    final categoryOrder = FoodCategoryData.kCategories;
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final ia = categoryOrder.indexOf(a.key);
        final ib = categoryOrder.indexOf(b.key);
        return (ia == -1 ? 999 : ia) - (ib == -1 ? 999 : ib);
      });
    return entries;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? Colors.red[600] : Colors.green[600],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _getCategoryName(String key) {
    return localizeCategory(key, AppLocalizations.of(context));
  }

  String _formatExpiry(Timestamp ts) {
    final lang = Localizations.localeOf(context).languageCode;
    final dateLocale =
        lang == 'tr' ? 'tr_TR' : (lang == 'ru' ? 'ru_RU' : 'en_US');
    return DateFormat('d MMM, HH:mm', dateLocale).format(ts.toDate());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    if (_loading) return _buildLoadingState(isDark);
    if (_error != null) return _buildErrorState(l10n);

    return RefreshIndicator(
      color: const Color(0xFFFF6200),
      onRefresh: _fetchFoods,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Header row with food count + Add button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_foods.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        l10n.foodCount(_foods.length),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  _AddFoodButton(restaurantId: widget.restaurantId),
                ],
              ),
            ),
          ),

          // Empty state
          if (_foods.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(l10n, isDark),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ..._foodsByCategory.map((entry) {
                    final category = entry.key;
                    final items = entry.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category header
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 10),
                          child: Row(
                            children: [
                              Text(
                                _getCategoryName(category),
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isDark ? Colors.white : Colors.grey[900],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${items.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Food cards
                        ...items.map((food) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FoodCard(
                                food: food,
                                isDark: isDark,
                                formatExpiry: _formatExpiry,
                                onToggleAvailability: () =>
                                    _toggleAvailability(food),
                                onEditFood: () => context.push(
                                    '/restaurant_list_food_screen?edit=${food.id}'),
                                onDiscountTap: () => _showDiscountModal(food),
                              ),
                            )),
                      ],
                    );
                  }).toList(),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Discount Modal ────────────────────────────────────────────────────────

  void _showDiscountModal(FoodItem food) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DiscountModal(
        food: food,
        onApply: (pct, start, end) => _applyDiscount(food, pct, start, end),
        onRemove: () => _removeDiscount(food),
      ),
    );
  }

  // ── Loading / Error / Empty ───────────────────────────────────────────────

  Widget _buildLoadingState(bool isDark) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(l10n.fetchError,
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchFoods,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6200)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orange.withOpacity(0.1)
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.restaurant_menu_rounded,
                  size: 40, color: Color(0xFFFF6200)),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noFoodsFound,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.startByAddingFood,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _AddFoodButton(restaurantId: widget.restaurantId, isLarge: true),
          ],
        ),
      ),
    );
  }
}

// ─── Food Card ────────────────────────────────────────────────────────────────

class _FoodCard extends StatelessWidget {
  final FoodItem food;
  final bool isDark;
  final String Function(Timestamp) formatExpiry;
  final VoidCallback onToggleAvailability;
  final VoidCallback onEditFood;
  final VoidCallback onDiscountTap;

  const _FoodCard({
    required this.food,
    required this.isDark,
    required this.formatExpiry,
    required this.onToggleAvailability,
    required this.onEditFood,
    required this.onDiscountTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = food.discount?.isActive ?? false;
    final expired = food.discount?.isExpired ?? false;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (food.imageUrl.isNotEmpty)
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: food.imageUrl,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 96,
                      height: 96,
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey[50],
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.grey[300], size: 24),
                    ),
                  ),
                ),
                // Discount badge on image
                if (active && food.discount != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '-${food.discount!.percentage}%',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else if (expired)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.discountExpired,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + availability toggle
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          food.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onToggleAvailability,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: food.isAvailable
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: food.isAvailable
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFFF87171),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    food.isAvailable
                                        ? l10n.available
                                        : l10n.unavailable,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: food.isAvailable
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.tapToChange,
                              style: GoogleFonts.inter(
                                  fontSize: 8, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Price row
                  Row(
                    children: [
                      if (active && food.discount != null) ...[
                        Text(
                          '${food.discount!.originalPrice.toStringAsFixed(2)} TL',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey[400],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${food.price.toStringAsFixed(2)} TL',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ] else if (expired && food.discount != null) ...[
                        Text(
                          '${food.price.toStringAsFixed(2)} TL',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${l10n.originalPrice2}: ${food.discount!.originalPrice.toStringAsFixed(2)} TL)',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ] else ...[
                        Text(
                          '${food.price.toStringAsFixed(2)} TL',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.grey[900],
                          ),
                        ),
                      ],
                      if (food.preparationTime != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.access_time_rounded,
                            size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 2),
                        Text(
                          '${food.preparationTime!} ${l10n.minutes}',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: Colors.grey[400]),
                        ),
                      ],
                    ],
                  ),

                  // Expiry info
                  if (active && food.discount != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      l10n.discountExpires(
                          formatExpiry(food.discount!.endDate)),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Action buttons
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.edit_outlined,
                        label: l10n.edit,
                        color: Colors.grey[500]!,
                        onTap: onEditFood,
                      ),
                      const SizedBox(width: 16),
                      _ActionBtn(
                        icon: Icons.percent_rounded,
                        label: active
                            ? l10n.editDiscount
                            : (expired ? l10n.editDiscount : l10n.discount),
                        color: active
                            ? const Color(0xFF10B981)
                            : (expired
                                ? const Color(0xFFF59E0B)
                                : Colors.grey[500]!),
                        onTap: onDiscountTap,
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
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Add Food Button ──────────────────────────────────────────────────────────

class _AddFoodButton extends StatelessWidget {
  final String restaurantId;
  final bool isLarge;

  const _AddFoodButton({required this.restaurantId, this.isLarge = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ElevatedButton.icon(
      onPressed: () => context
          .push('/restaurant_list_food_screen?restaurantId=$restaurantId'),
      icon: Icon(Icons.add_rounded, size: isLarge ? 18 : 15),
      label: Text(
        l10n.addFood,
        style: GoogleFonts.inter(
          fontSize: isLarge ? 14 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF6200),
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
            horizontal: isLarge ? 20 : 14, vertical: isLarge ? 12 : 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isLarge ? 14 : 10)),
        elevation: 0,
      ),
    );
  }
}

// ─── Discount Modal ───────────────────────────────────────────────────────────

class _DiscountModal extends StatefulWidget {
  final FoodItem food;
  final Future<void> Function(int pct, DateTime start, DateTime end) onApply;
  final Future<void> Function() onRemove;

  const _DiscountModal({
    required this.food,
    required this.onApply,
    required this.onRemove,
  });

  @override
  State<_DiscountModal> createState() => _DiscountModalState();
}

class _DiscountModalState extends State<_DiscountModal> {
  late int _percentage;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hasActive = widget.food.discount?.isActive ?? false;
    _percentage = hasActive ? (widget.food.discount?.percentage ?? 10) : 10;
    _startDate = DateTime.now();
    _endDate = DateTime.now().add(const Duration(hours: 24));
  }

  double get _basePrice {
    final d = widget.food.discount;
    if (d != null && (d.isActive || d.isExpired)) return d.originalPrice;
    return widget.food.price;
  }

  double get _discountedPrice =>
      (_basePrice * (1 - _percentage / 100) * 100).roundToDouble() / 100;

  bool get _hasExistingDiscount =>
      widget.food.discount != null &&
      (widget.food.discount!.isActive || widget.food.discount!.isExpired);

  Future<void> _handleApply() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);

    if (_percentage < _minDiscount || _percentage > _maxDiscount) {
      setState(() => _error = l10n.percentRange(_maxDiscount, _minDiscount));
      return;
    }
    if (_endDate.isBefore(_startDate) ||
        _endDate.isAtSameMomentAs(_startDate)) {
      setState(() => _error = l10n.endBeforeStart);
      return;
    }
    if (_endDate.isBefore(DateTime.now())) {
      setState(() => _error = l10n.endInPast);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onApply(_percentage, _startDate, _endDate);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = l10n.discountError;
          _saving = false;
        });
      }
    }
  }

  Future<void> _handleRemove() async {
    setState(() => _saving = true);
    try {
      await widget.onRemove();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).discountError;
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final hasActive = widget.food.discount?.isActive ?? false;

    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.percent_rounded,
                      size: 18, color: Color(0xFFFF6200)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasActive ? l10n.editDiscount : l10n.addDiscount,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.grey[900],
                        ),
                      ),
                      Text(
                        widget.food.name,
                        style: GoogleFonts.inter(
                            fontSize: 11, color: Colors.grey[400]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded,
                      color: isDark ? Colors.white54 : Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Percentage slider + input
            Text(
              l10n.discountPercentage,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFFF6200),
                      thumbColor: const Color(0xFFFF6200),
                      inactiveTrackColor: Colors.grey[200],
                      overlayColor: const Color(0xFFFF6200).withOpacity(0.1),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _percentage.toDouble(),
                      min: _minDiscount.toDouble(),
                      max: _maxDiscount.toDouble(),
                      divisions: _maxDiscount - _minDiscount,
                      onChanged: (v) => setState(() => _percentage = v.round()),
                    ),
                  ),
                ),
                Container(
                  width: 60,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Text(
                    '$_percentage%',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF6200),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            Text(
              l10n.percentRange(_maxDiscount, _minDiscount),
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),

            // Date pickers
            Row(
              children: [
                Expanded(
                  child: _DatePickerTile(
                    label: l10n.startDate,
                    date: _startDate,
                    isDark: isDark,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DatePickerTile(
                    label: l10n.endDate,
                    date: _endDate,
                    isDark: isDark,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Price preview
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    isDark ? Colors.white.withOpacity(0.04) : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.originalPrice2,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey[500])),
                      Text(
                        '${_basePrice.toStringAsFixed(2)} TL',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[500],
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.discountedPrice,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF059669),
                          )),
                      Text(
                        '${_discountedPrice.toStringAsFixed(2)} TL',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Error
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(_error!,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.red[700])),
              ),

            // Action buttons
            Row(
              children: [
                if (_hasExistingDiscount)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _handleRemove,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: Text(l10n.removeDiscount,
                          style: GoogleFonts.inter(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[50],
                        foregroundColor: Colors.red[600],
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[600],
                      side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(l10n.cancel,
                        style: GoogleFonts.inter(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _handleApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6200),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(l10n.apply,
                            style: GoogleFonts.inter(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ─── Date Picker Tile ─────────────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final bool isDark;
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final dateLocale =
        lang == 'tr' ? 'tr_TR' : (lang == 'ru' ? 'ru_RU' : 'en_US');
    final formatted = DateFormat('d MMM, HH:mm', dateLocale).format(date);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 13, color: Colors.grey[400]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatted,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.grey[800],
                    ),
                    overflow: TextOverflow.ellipsis,
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

