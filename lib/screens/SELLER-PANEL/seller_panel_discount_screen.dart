import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../widgets/product_card_4.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../constants/all_in_one_category_data.dart';
import '../../../providers/seller_panel_provider.dart';
import '../../../models/product.dart';

class SellerPanelDiscountScreen extends StatefulWidget {
  const SellerPanelDiscountScreen({Key? key}) : super(key: key);

  @override
  State<SellerPanelDiscountScreen> createState() =>
      _SellerPanelDiscountScreenState();
}

class _SellerPanelDiscountScreenState extends State<SellerPanelDiscountScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late final FocusNode _searchFocus;
  late final TextEditingController _searchCtrl;
  late final ScrollController _scrollCtrl;
  Timer? _debounce;

  // Initial load tracking for shimmer
  bool _isInitialLoad = true;
  Timer? _initialLoadSafetyTimer;
  static const Duration _maxInitialLoadDuration = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _searchFocus = FocusNode();
    _searchCtrl = TextEditingController();

    _searchCtrl.addListener(() {
  final provider = Provider.of<SellerPanelProvider>(context, listen: false);

  // Immediate UI feedback - show that search is starting
  if (_searchCtrl.text.trim().isNotEmpty && !provider.isSearchMode) {
    provider.setSearchModeImmediate(true);
  } else if (_searchCtrl.text.trim().isEmpty && provider.isSearchMode) {
    provider.setSearchModeImmediate(false);
  }

  // Debounced search execution
  if (_debounce?.isActive ?? false) _debounce!.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    if (mounted) {
      provider.setSearchQuery(_searchCtrl.text);
    }
  });
});

_scrollCtrl = ScrollController();

// Add scroll listener for infinite scroll
_scrollCtrl.addListener(() {
  if (_scrollCtrl.position.extentAfter < 600) {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    
    if (provider.isSearchMode) {
      if (!provider.isLoadingMoreSearchResultsNotifier.value &&
          provider.hasMoreSearchResults) {
        provider.loadMoreSearchResults();
      }
    }
    // Note: Regular products don't need infinite scroll in discount screen
  }
});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      provider.initialize().then((_) {
        _endInitialLoad();
      }).catchError((error) {
        debugPrint('Error initializing discount screen: $error');
        _endInitialLoad();
      });
      _fadeController.forward();

      // Safety timer to prevent stuck shimmer
      _initialLoadSafetyTimer = Timer(_maxInitialLoadDuration, () {
        debugPrint('⚠️ Discount screen initial load safety timer triggered');
        _endInitialLoad();
      });
    });
  }

  void _endInitialLoad() {
    _initialLoadSafetyTimer?.cancel();
    _initialLoadSafetyTimer = null;
    if (mounted && _isInitialLoad) {
      setState(() => _isInitialLoad = false);
    }
  }

  @override
  void dispose() {
    _initialLoadSafetyTimer?.cancel();
    _scrollCtrl.dispose();
    _fadeController.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _searchFocus.unfocus(),
      child: Scaffold(
        backgroundColor: isDarkMode
            ? const Color(0xFF1C1A29)
            : Color.fromARGB(255, 244, 244, 244),
        body: SafeArea(
          child: Consumer<SellerPanelProvider>(
            builder: (context, provider, child) {
              // Show shimmer during initial load
              if (_isInitialLoad) {
                return _buildInitialLoadShimmer(isDarkMode);
              }

              // Add comprehensive null checks
              if (provider.isLoadingShops && provider.shops.isEmpty) {
                return _buildInitialLoadShimmer(isDarkMode);
              }
              if (provider.shops.isEmpty) {
                return _buildEmptyState(l10n.noShopSelected, isDarkMode);
              }
              if (provider.selectedShop == null) {
                return _buildEmptyState(l10n.noShopSelected, isDarkMode);
              }

              return FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    _buildCompactHeader(context, l10n, isDarkMode),
                    _buildSearchBar(context, l10n, isDarkMode),
                    _buildCompactControls(context, provider, l10n, isDarkMode),
                    Expanded(
                      child: _buildProductsList(
                          context, provider, l10n, isDarkMode),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(
      BuildContext context, AppLocalizations l10n, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1C1A29)
            : Colors.white.withOpacity(0.8),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color:
                  isDarkMode ? Colors.black26 : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: TextField(
          focusNode: _searchFocus,
          controller: _searchCtrl,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            prefixIcon: Container(
  margin: const EdgeInsets.all(8),
  child: Consumer<SellerPanelProvider>(
    builder: (context, provider, _) {
      return ValueListenableBuilder<bool>(
        valueListenable: provider.isSearchingNotifier,
        builder: (context, isSearching, _) {
          if (isSearching) {
            return SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDarkMode ? Colors.tealAccent : Colors.teal,
                ),
              ),
            );
          }
          return Icon(
            Icons.search_rounded,
            size: 18,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
          );
        },
      );
    },
  ),
),
            suffixIcon: Consumer<SellerPanelProvider>(
  builder: (context, provider, _) {
    if (_searchCtrl.text.isNotEmpty) {
      return GestureDetector(
        onTap: () {
          _searchCtrl.clear();
          provider.setSearchQuery('');
        },
        child: Container(
          margin: const EdgeInsets.all(8),
          child: Icon(
            Icons.clear_rounded,
            size: 16,
            color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.all(6),
      child: Icon(
        Icons.tune_rounded,
        size: 16,
        color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
      ),
    );
  },
),
            hintText: l10n.searchProducts,
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            filled: true,
            fillColor: isDarkMode ? const Color(0xFF2A2D3A) : Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade200,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.tealAccent : Colors.teal,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialLoadShimmer(bool isDarkMode) {
    return Shimmer.fromColors(
      baseColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade100,
      child: Column(
        children: [
          // Header shimmer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 150,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          // Search bar shimmer
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Controls shimmer
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Products list shimmer
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (context, index) => _buildProductCardShimmer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCardShimmer() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Product image placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 80,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsLoadingShimmer(bool isDarkMode) {
    return Shimmer.fromColors(
      baseColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300,
      highlightColor: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 5,
        itemBuilder: (context, index) => _buildProductCardShimmer(),
      ),
    );
  }

  Widget _buildEmptyState(String message, bool isDarkMode) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_outlined,
              size: 48,
              color: isDarkMode ? Colors.white30 : const Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactHeader(
      BuildContext context, AppLocalizations l10n, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Color.fromARGB(255, 33, 31, 49)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: isDarkMode ? Colors.white : const Color(0xFF333333),
                size: 18,
              ),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.applyDiscount,
              style: TextStyle(
                color: isDarkMode ? Colors.white : const Color(0xFF333333),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactControls(BuildContext context,
      SellerPanelProvider provider, AppLocalizations l10n, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Filters Row
          Row(
            children: [
              Expanded(
                child: _buildCompactFilterChip(
                  context,
                  provider.selectedCategory != null
                      ? AllInOneCategoryData.localizeCategoryKey(
                          provider.selectedCategory!, l10n)
                      : l10n.selectCategory,
                  Icons.category_outlined,
                  () => _showCategoryPicker(context, provider),
                  isDarkMode,
                ),
              ),
              if (provider.selectedCategory != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactFilterChip(
                    context,
                    provider.selectedSubcategory != null
                        ? AllInOneCategoryData.localizeSubcategoryKey(
                            provider.selectedCategory!,
                            provider.selectedSubcategory!,
                            l10n)
                        : l10n.selectSubcategory,
                    Icons.tune_outlined,
                    () => _showSubcategoryPicker(context, provider),
                    isDarkMode,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Action Buttons Row 1
          Row(
            children: [
              Expanded(
                child: _buildCompactActionButton(
                  l10n.bulkDiscount,
                  Icons.discount_outlined,
                  const Color(0xFF007AFF),
                  () => _showBulkDiscountModal(context),
                  isDarkMode,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactActionButton(
                  l10n.categoryBasedDiscount,
                  Icons.category_outlined,
                  const Color(0xFF34C759),
                  () => _showCategoryDiscountModal(context, provider),
                  isDarkMode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Action Buttons Row 2 - Remove Discounts
          Row(
            children: [
              Expanded(
                child: _buildCompactActionButton(
                  l10n.removeAllDiscounts, // Use localized text
                  Icons.clear_outlined,
                  const Color(0xFFFF9500),
                  () => _processBulkRemoveDiscounts(l10n),
                  isDarkMode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFilterChip(BuildContext context, String label,
      IconData icon, VoidCallback onTap, bool isDarkMode) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Color.fromARGB(255, 33, 31, 49)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDarkMode
                ? Color.fromARGB(255, 33, 31, 49)
                : const Color(0xFFE0E0E0),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionButton(String label, IconData icon, Color color,
      VoidCallback onPressed, bool isDarkMode) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        // Removed boxShadow to eliminate glow effect
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductsList(BuildContext context, SellerPanelProvider provider,
      AppLocalizations l10n, bool isDarkMode) {
    // Provider is already passed from parent Consumer - no need for nested Consumer
    if (provider.isLoadingProducts && !provider.isSearchMode) {
      return _buildProductsLoadingShimmer(isDarkMode);
    }

    return provider.isSearchMode
        ? _buildSearchResults(context, l10n, isDarkMode)
        : _buildRegularProducts(context, provider, l10n, isDarkMode);
  }

  Widget _buildSearchResults(BuildContext context, AppLocalizations l10n, bool isDarkMode) {
    return ValueListenableBuilder<bool>(
      valueListenable: context.read<SellerPanelProvider>().isSearchingNotifier,
      builder: (context, isSearching, _) {
        if (isSearching) {
          return _buildProductsLoadingShimmer(isDarkMode);
        }

      return ValueListenableBuilder<List<Product>>(
        valueListenable: context.read<SellerPanelProvider>().searchResultsNotifier,
        builder: (context, searchResults, _) {
          if (searchResults.isEmpty) {
            return _buildEmptyState(l10n.noProductsFound, isDarkMode);
          }

          return _buildProductGrid(context, searchResults, l10n, isDarkMode, isSearchMode: true);
        },
      );
    },
  );
}

Widget _buildRegularProducts(BuildContext context, SellerPanelProvider provider, 
    AppLocalizations l10n, bool isDarkMode) {
  final filteredProducts = provider.filteredProducts;
  
  if (filteredProducts.isEmpty) {
    return _buildEmptyState(l10n.noProductsFound, isDarkMode);
  }

  return _buildProductGrid(context, filteredProducts, l10n, isDarkMode, isSearchMode: false);
}

Widget _buildProductGrid(BuildContext context, List<Product> products, 
    AppLocalizations l10n, bool isDarkMode, {required bool isSearchMode}) {
  
  return Column(
    children: [
      // Search results header (only for search mode)
      if (isSearchMode) ...[
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (isDarkMode ? Colors.tealAccent : Colors.teal).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isDarkMode ? Colors.tealAccent : Colors.teal).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 16,
                color: isDarkMode ? Colors.tealAccent : Colors.teal,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.searchResultsCount(products.length.toString()),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.tealAccent : Colors.teal,
                ),
              ),
            ],
          ),
        ),
      ],
      
      // Products list
      Expanded(
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return _buildCompactProductCard(context, product, l10n, isDarkMode);
          },
        ),
      ),
      
      // Load more indicator
      if (isSearchMode)
        ValueListenableBuilder<bool>(
          valueListenable: context.read<SellerPanelProvider>().isLoadingMoreSearchResultsNotifier,
          builder: (context, isLoadingMore, _) {
            if (!isLoadingMore) return const SizedBox.shrink();
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CupertinoActivityIndicator(
                  radius: 14,
                  color: Color(0xFF007AFF),
                ),
              ),
            );
          },
        ),
    ],
  );
}

  Widget _buildCompactProductCard(BuildContext context, Product product,
      AppLocalizations l10n, bool isDarkMode) {
    final hasDiscount = product.discountPercentage != null;
    final hasSalePreference = product.discountThreshold != null &&
                               product.bulkDiscountPercentage != null &&
                               product.discountThreshold! > 0 &&
                               product.bulkDiscountPercentage! > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.push(
              '/seller_panel_product_detail',
              extra: {'product': product, 'productId': product.id},
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Use ProductCard4 widget directly
                Expanded(
                  child: ProductCard4(
                    imageUrl: product.imageUrls.isNotEmpty
                        ? product.imageUrls[0]
                        : '',
                    colorImages: product.colorImages,
                    selectedColor: null,
                    productName: product.productName.isNotEmpty
                        ? product.productName
                        : l10n.unnamedProduct,
                    brandModel:
                        '', // Pass empty string to force display of productName
                    price: product.price,
                    currency: product.currency,
                    averageRating: product.averageRating,
                    productId: product.id,
                    originalPrice: product.originalPrice,
                    discountPercentage: product.discountPercentage,
                    showOverlayIcons:
                        false, // Disable overlay icons for seller panel
                    isShopProduct: true,
                  ),
                ),
                const SizedBox(width: 12),
                // Action buttons column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasSalePreference) ...[
                      // Show warning when sale preference exists
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Sale Pref.',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildCompactActionChip(
                        l10n.remove,
                        Colors.red,
                        () => _removeSalePreference(context, product),
                      ),
                    ] else ...[
                      _buildCompactActionChip(
                        hasDiscount ? l10n.removeDiscount : l10n.applyDiscount,
                        hasDiscount
                            ? const Color(0xFFFF9500)
                            : const Color(0xFF007AFF),
                        hasDiscount
                            ? () => _removeIndividualDiscount(context, product)
                            : () =>
                                _showIndividualDiscountModal(context, product),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${product.discountPercentage}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactActionChip(
      String label, Color color, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Keep all the existing modal and functionality methods with loading indicators
  void _showCategoryPicker(BuildContext context, SellerPanelProvider provider) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => AnimatedPadding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        child: CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                provider.setCategory(null);
                Navigator.pop(context);
              },
              child: Text(l10n.none,
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black)),
            ),
            ...AllInOneCategoryData.kCategories.map((category) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  _clearSearch();
                  provider.setCategory(category['key']);
                  Navigator.pop(context);
                },
                child: Text(
                  AllInOneCategoryData.localizeCategoryKey(
                      category['key']!, l10n),
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black),
                ),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

  void _showSubcategoryPicker(
      BuildContext context, SellerPanelProvider provider) {
    if (provider.selectedCategory == null) return;
    final l10n = AppLocalizations.of(context);
    final subcategories =
        AllInOneCategoryData.kSubcategories[provider.selectedCategory] ?? [];
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => AnimatedPadding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        child: CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                provider.setSubcategory(null);
                Navigator.pop(context);
              },
              child: Text(l10n.none,
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black)),
            ),
            ...subcategories.map((subcategory) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  provider.setSubcategory(subcategory);
                  Navigator.pop(context);
                },
                child: Text(
                  AllInOneCategoryData.localizeSubcategoryKey(
                      provider.selectedCategory!, subcategory, l10n),
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black),
                ),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

  bool _canSafelyPop(BuildContext context) {
    if (!mounted) return false;
    try {
      return Navigator.canPop(context);
    } catch (e) {
      // Context is no longer valid
      return false;
    }
  }

  // Helper method to safely pop navigator
  void _safelyPop(BuildContext context) {
    if (_canSafelyPop(context)) {
      Navigator.pop(context);
    }
  }

  // Helper method to safely show snackbar
  void _safelyShowSnackBar(BuildContext context, String? message) {
    if (mounted && message != null && message.isNotEmpty) {
      try {
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
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        // Context is no longer valid, ignore
        debugPrint('Failed to show snackbar: $e');
      }
    }
  }

  void _showBulkDiscountModal(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
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
                  maxHeight: MediaQuery.of(context).size.height * 0.5, // Reduced from 0.6
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
                                colors: [const Color(0xFF007AFF), Colors.blue.shade600],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.discount_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.bulkDiscount,
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
                                color: const Color(0xFF007AFF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF007AFF).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: const Color(0xFF007AFF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.bulkDiscountHelper ?? 
                                      'Apply discount to all filtered products without existing discounts',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: const Color(0xFF007AFF),
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
                                      : (isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                                  width: _isValidDiscount(controller.text) ? 2 : 1,
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
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      onChanged: (_) => setState(() {}),
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white : Colors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '1-100',
                                        hintStyle: TextStyle(
                                          color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(
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
                                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
                            if (controller.text.isNotEmpty && !_isValidDiscount(controller.text))
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
                                        l10n.validDiscountMessage ?? 'Valid discount percentage',
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
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
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
                                      final input = int.parse(controller.text);
                                      Navigator.pop(context);
                                      await _processBulkDiscount(input, l10n);
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

  Future<void> _processBulkDiscount(
      int percentage, AppLocalizations l10n) async {
    if (!mounted) return;

    // Show loading overlay
    OverlayEntry? loadingOverlay;
    try {
      loadingOverlay = _createLoadingOverlay(
          l10n.applyingDiscount ?? 'Applying discount...');
      Overlay.of(context).insert(loadingOverlay);

      await _applyBulkDiscount(percentage);

      // Remove loading overlay
      loadingOverlay.remove();
      loadingOverlay = null;

      if (mounted) {
        _safelyShowSnackBar(
            context, l10n.discountApplied ?? 'Discount applied successfully');
      }
    } catch (e) {
      debugPrint('Error in bulk discount: $e');

      // Ensure loading overlay is removed
      loadingOverlay?.remove();

      if (mounted) {
        _safelyShowSnackBar(context, 'Error applying discount: $e');
      }
    }
  }

  bool _isValidDiscount(String input) {
  final value = int.tryParse(input);
  return value != null && value >= 1 && value <= 100;
}

  OverlayEntry _createLoadingOverlay(String message) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return OverlayEntry(
      builder: (context) => Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(
                  radius: 14,
                  color: Color(0xFF007AFF),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyBulkDiscount(int percentage) async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    if (provider.selectedShop == null) {
      throw Exception('No shop selected');
    }

    final selectedShopId = provider.selectedShop!.id;

    // Get products based on current filters - use a more efficient approach
    List<Product> targetProducts =
        await _getFilteredProductsForBulkOperation(provider, selectedShopId);

    if (targetProducts.isEmpty) {
      throw Exception('No products found to apply discount');
    }

    // Filter out products that already have discounts
    final productsToUpdate = targetProducts
        .where((product) =>
            product.discountPercentage == null && product.reference != null)
        .toList();

    if (productsToUpdate.isEmpty) {
      throw Exception('All products already have discounts');
    }

    debugPrint('Applying bulk discount to ${productsToUpdate.length} products');

    // Process in batches to avoid Firestore limits and improve performance
    const int batchSize = 500; // Firestore batch limit
    final int totalBatches = (productsToUpdate.length / batchSize).ceil();

    for (int i = 0; i < totalBatches; i++) {
      final startIndex = i * batchSize;
      final endIndex =
          (startIndex + batchSize).clamp(0, productsToUpdate.length);
      final batchProducts = productsToUpdate.sublist(startIndex, endIndex);

      await _processBatch(
          batchProducts, percentage, provider, i + 1, totalBatches);

      // Small delay between batches to prevent overwhelming Firestore
      if (i < totalBatches - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    debugPrint(
        'Successfully applied bulk discount to ${productsToUpdate.length} products');
  }

 Future<List<Product>> _getFilteredProductsForBulkOperation(
    SellerPanelProvider provider, String selectedShopId) async {
  
  List<Product> allShopProducts;
  
  // IMPORTANT: Use search results when in search mode
  if (provider.isSearchMode) {
    allShopProducts = provider.searchResultsNotifier.value.where((product) {
      return product.shopId == selectedShopId;
    }).toList();
  } else {
    // Use filtered products for regular mode
    allShopProducts = provider.filteredProducts.where((product) {
      return product.shopId == selectedShopId;
    }).toList();

    // Apply category/subcategory filters (only in regular mode)
    if (provider.selectedCategory != null) {
      allShopProducts = allShopProducts.where((product) {
        bool matchesCategory = product.category == provider.selectedCategory;

        if (provider.selectedSubcategory != null) {
          return matchesCategory &&
              product.subcategory == provider.selectedSubcategory;
        }

        return matchesCategory;
      }).toList();
    }
  }

  return allShopProducts;
}

void _clearSearch() {
  _searchCtrl.clear();
  final provider = Provider.of<SellerPanelProvider>(context, listen: false);
  provider.setSearchQuery('');
}

  Future<void> _processBatch(List<Product> products, int percentage,
      SellerPanelProvider provider, int currentBatch, int totalBatches) async {
    final batch = FirebaseFirestore.instance.batch();
    final List<Product> successfulUpdates = [];

    for (var product in products) {
      try {
        if (product.reference == null) {
          debugPrint('Product ${product.id} has null reference, skipping');
          continue;
        }

        // Use current price as base price (should be clean price without discounts)
        final double basePrice = product.price;
        final double newPrice = double.parse(
            (basePrice * (1 - percentage / 100)).toStringAsFixed(2));

        batch.update(product.reference!, {
          'originalPrice': basePrice, // Store exact current price
          'discountPercentage': percentage,
          'price': newPrice,
        });

        successfulUpdates.add(product);
      } catch (e) {
        debugPrint('Error preparing update for product ${product.id}: $e');
      }
    }

    if (successfulUpdates.isEmpty) {
      debugPrint('No valid products in batch $currentBatch');
      return;
    }

    try {
      // Commit batch to Firestore
      await batch.commit();

      // Update local state only after successful Firestore commit
      for (var product in successfulUpdates) {
        final double basePrice = product.price;
        final double newPrice = double.parse(
            (basePrice * (1 - percentage / 100)).toStringAsFixed(2));

        provider.updateProduct(
          product.id,
          product.copyWith(
            price: newPrice,
            originalPrice: basePrice, // Store exact current price
            discountPercentage: percentage,
          ),
        );
      }

      debugPrint(
          'Successfully processed batch $currentBatch/$totalBatches (${successfulUpdates.length} products)');
    } catch (e) {
      debugPrint('Error committing batch $currentBatch: $e');
      throw Exception('Failed to update products in batch $currentBatch: $e');
    }
  }

  void _showCategoryDiscountModal(
      BuildContext context, SellerPanelProvider provider) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => AnimatedPadding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        child: CupertinoActionSheet(
          title: Text(l10n.selectCategory),
          actions: AllInOneCategoryData.kCategories.map((category) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showSubcategoryDiscountModal(
                    context, provider, category['key']!);
              },
              child: Text(
                AllInOneCategoryData.localizeCategoryKey(
                    category['key']!, l10n),
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

  void _showSubcategoryDiscountModal(
      BuildContext context, SellerPanelProvider provider, String category) {
    final l10n = AppLocalizations.of(context);
    final subcategories = AllInOneCategoryData.kSubcategories[category] ?? [];
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showCupertinoModalPopup(
      context: context,
      builder: (context) => AnimatedPadding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        child: CupertinoActionSheet(
          title: Text(l10n.selectSubcategory),
          actions: subcategories.map((subcategory) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showDiscountPercentageModal(context, category, subcategory);
              },
              child: Text(
                AllInOneCategoryData.localizeSubcategoryKey(
                    category, subcategory, l10n),
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel,
                style:
                    TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
          ),
        ),
      ),
    );
  }

 void _showDiscountPercentageModal(
    BuildContext context, String category, String subcategory) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  showCupertinoModalPopup(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
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
                  maxHeight: MediaQuery.of(context).size.height * 0.5, // Reduced from 0.6
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
                                colors: [const Color(0xFF34C759), Colors.green.shade600],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.category_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.categoryBasedDiscount,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
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
                            // Category info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF34C759).withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.category_outlined,
                                        color: const Color(0xFF34C759),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${AllInOneCategoryData.localizeCategoryKey(category, l10n)} > ${AllInOneCategoryData.localizeSubcategoryKey(category, subcategory, l10n)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: const Color(0xFF34C759),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.categoryDiscountHelper ?? 
                                    'Apply discount to all products in this category',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: const Color(0xFF34C759),
                                      fontWeight: FontWeight.w500,
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
                                      : (isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                                  width: _isValidDiscount(controller.text) ? 2 : 1,
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
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      onChanged: (_) => setState(() {}),
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white : Colors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '1-100',
                                        hintStyle: TextStyle(
                                          color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(
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
                                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
                            if (controller.text.isNotEmpty && !_isValidDiscount(controller.text))
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
                                        l10n.validDiscountMessage ?? 'Valid discount percentage',
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
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
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
                                  ? const Color(0xFF34C759)
                                  : CupertinoColors.inactiveGray,
                              onPressed: _isValidDiscount(controller.text)
                                  ? () async {
                                      final input = int.parse(controller.text);
                                      Navigator.pop(context);
                                      await _processCategoryDiscount(category, subcategory, input, l10n);
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

  Future<void> _processCategoryDiscount(String category, String subcategory,
      int percentage, AppLocalizations l10n) async {
    if (!mounted) return;

    OverlayEntry? loadingOverlay;
    try {
      loadingOverlay = _createLoadingOverlay(
          l10n.applyingDiscount ?? 'Applying discount...');
      Overlay.of(context).insert(loadingOverlay);

      await _applyCategoryDiscount(category, subcategory, percentage);

      loadingOverlay.remove();
      loadingOverlay = null;

      if (mounted) {
        _safelyShowSnackBar(
            context, l10n.discountApplied ?? 'Discount applied successfully');
      }
    } catch (e) {
      debugPrint('Error in category discount: $e');
      loadingOverlay?.remove();

      if (mounted) {
        _safelyShowSnackBar(context, 'Error applying discount: $e');
      }
    }
  }

  Future<void> _applyCategoryDiscount(
      String category, String subcategory, int percentage) async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    if (provider.selectedShop == null) {
      throw Exception('No shop selected');
    }

    final selectedShopId = provider.selectedShop!.id;
    final filteredProducts = provider.filteredProducts.where((product) {
      return product.shopId == selectedShopId &&
          product.category == category &&
          product.subcategory == subcategory;
    }).toList();

    if (filteredProducts.isEmpty) {
      throw Exception('No products found in this category');
    }

    // Filter out products that already have discounts and have valid references
    final productsToUpdate = filteredProducts
        .where((product) =>
            product.discountPercentage == null && product.reference != null)
        .toList();

    if (productsToUpdate.isEmpty) {
      throw Exception('All products in this category already have discounts');
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var product in productsToUpdate) {
        final double basePrice = product.price;
        final double newPrice = double.parse(
            (basePrice * (1 - percentage / 100)).toStringAsFixed(2));

        batch.update(product.reference!, {
          'originalPrice': basePrice,
          'discountPercentage': percentage,
          'price': newPrice,
        });
      }

      await batch.commit();

      // Update local state only after successful Firestore commit
      for (var product in productsToUpdate) {
        final double basePrice = product.price;
        final double newPrice = double.parse(
            (basePrice * (1 - percentage / 100)).toStringAsFixed(2));

        provider.updateProduct(
          product.id,
          product.copyWith(
            price: newPrice,
            originalPrice: basePrice,
            discountPercentage: percentage,
          ),
        );
      }

      debugPrint(
          'Successfully applied category discount to ${productsToUpdate.length} products');
    } catch (e) {
      debugPrint('Error in _applyCategoryDiscount: $e');
      throw e;
    }
  }

 void _showIndividualDiscountModal(BuildContext context, Product product) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController();
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  showCupertinoModalPopup(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
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
                  maxHeight: MediaQuery.of(context).size.height * 0.6, // Reduced from 0.7
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
                                colors: [const Color(0xFF007AFF), Colors.blue.shade600],
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
                          Expanded(
                            child: Text(
                              l10n.enterDiscountPercentage,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
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
                            // Product info
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDarkMode 
                                    ? const Color.fromARGB(255, 45, 43, 61)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Product image
                                  if (product.imageUrls.isNotEmpty)
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image: NetworkImage(product.imageUrls.first),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  
                                  // Product details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.productName.isNotEmpty 
                                              ? product.productName 
                                              : l10n.unnamedProduct,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isDarkMode ? Colors.white : Colors.black,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${product.price} ${product.currency}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade600,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Helper text
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF007AFF).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: const Color(0xFF007AFF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.individualDiscountHelper ?? 
                                      'Enter a discount percentage for this product',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: const Color(0xFF007AFF),
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
                                      : (isDarkMode ? Colors.grey[600]! : Colors.grey[300]!),
                                  width: _isValidDiscount(controller.text) ? 2 : 1,
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
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      onChanged: (_) => setState(() {}),
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white : Colors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '1-100',
                                        hintStyle: TextStyle(
                                          color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(
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
                                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
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
                            if (controller.text.isNotEmpty && !_isValidDiscount(controller.text))
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
                            
                            // Success message with price preview
                            if (_isValidDiscount(controller.text))
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            l10n.validDiscountMessage ?? 'Valid discount percentage',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            l10n.newPrice ?? 'New price:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${(product.price * (1 - int.parse(controller.text) / 100)).toStringAsFixed(2)} ${product.currency}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w700,
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
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
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
                                      final input = int.parse(controller.text);
                                      Navigator.pop(context);
                                      await _processIndividualDiscount(product, input, l10n);
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

  Future<void> _processIndividualDiscount(
      Product product, int percentage, AppLocalizations l10n) async {
    if (!mounted) return;

    OverlayEntry? loadingOverlay;
    try {
      loadingOverlay = _createLoadingOverlay(
          l10n.applyingDiscount ?? 'Applying discount...');
      Overlay.of(context).insert(loadingOverlay);

      await _applyIndividualDiscount(product, percentage);

      loadingOverlay.remove();
      loadingOverlay = null;

      if (mounted) {
        _safelyShowSnackBar(
            context, l10n.discountApplied ?? 'Discount applied successfully');
      }
    } catch (e) {
      loadingOverlay?.remove();
      if (mounted) {
        _safelyShowSnackBar(context, 'Error applying discount: $e');
      }
    }
  }

  Future<void> _applyIndividualDiscount(Product product, int percentage) async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    if (product.reference == null) {
      throw Exception('Cannot update product: invalid reference');
    }

    try {
      // Use current price as base price (since discounts should be removed first)
      final double basePrice = product.price;
      final double newPrice =
          double.parse((basePrice * (1 - percentage / 100)).toStringAsFixed(2));

      // Update Firestore first
      await product.reference!.update({
        'originalPrice': basePrice, // Store the exact current price
        'discountPercentage': percentage,
        'price': newPrice,
      });

      // Create updated product with new values
      final updatedProduct = product.copyWith(
        price: newPrice,
        originalPrice: basePrice, // Store the exact current price
        discountPercentage: percentage,
      );

      // Update local state
      provider.updateProduct(product.id, updatedProduct);

      debugPrint(
          'Applied discount to product ${product.id}: $basePrice -> $newPrice (${percentage}% off)');
    } catch (e) {
      debugPrint('Error in _applyIndividualDiscount: $e');
      throw e;
    }
  }

 Future<void> _removeIndividualDiscount(
    BuildContext context, Product product) async {
  final l10n = AppLocalizations.of(context);
  if (!mounted) return;

  if (product.reference == null) {
    _safelyShowSnackBar(context, 'Cannot update product: invalid reference');
    return;
  }

  // ✅ FETCH FRESH DATA from Firestore to check campaign status
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
                          gradient: const LinearGradient(
                            colors: [Colors.blue, Colors.blueAccent],
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    );
                  },
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
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
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
    // ✅ Fetch fresh product data from Firestore
    final freshProductDoc = await product.reference!.get();
    
    // ✅ Close loading modal
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    if (!mounted) return;
    
    if (!freshProductDoc.exists) {
      _safelyShowSnackBar(context, l10n.productNotFound ?? 'Product not found');
      return;
    }
    
    final freshData = freshProductDoc.data() as Map<String, dynamic>;
    final campaignId = freshData['campaign'] as String?;
    final campaignName = freshData['campaignName'] as String?;
    
    // ✅ Check if product is in a campaign using fresh data
    if (campaignId != null && campaignName != null) {
      // ✅ CRITICAL FIX: Capture provider BEFORE showing modal
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      
      showCupertinoModalPopup(
        context: context,
        builder: (BuildContext modalContext) => CupertinoActionSheet(
          title: Text(
            l10n.removeFromCampaignTitle,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          message: Text(
            l10n.productInCampaignMessage(campaignName),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(modalContext);
                // ✅ Pass the captured provider to the processing method
                _processRemoveFromCampaignAndDiscountWithProvider(
                  context, product, provider);
              },
              isDestructiveAction: true,
              child: Text(
                l10n.removeFromCampaignAndDiscount,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.destructiveRed,
                ),
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(modalContext),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
      return;
    }
    
    // ✅ If not in campaign, proceed with normal discount removal
    await _processRemoveDiscountOnlyWithProvider(context, product);
    
  } catch (e) {
    // ✅ Ensure loading modal is closed on error
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    if (mounted) {
      _safelyShowSnackBar(context, 'Error checking product: $e');
    }
  }
}

// ✅ NEW METHOD: Process discount removal with provider passed explicitly
Future<void> _processRemoveDiscountOnlyWithProvider(
    BuildContext context, Product product) async {
  final l10n = AppLocalizations.of(context);
  if (!mounted) return;

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
                            colors: [Colors.red.shade400, Colors.red.shade600],
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade400),
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
    
    final double basePrice = product.originalPrice ?? product.price;
    final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

    await product.reference!.update({
      'price': cleanPrice,
      'discountPercentage': null,
      'originalPrice': null,
    });

    final updatedProduct = product.copyWith(
      price: cleanPrice,
      setOriginalPriceNull: true,
      setDiscountPercentageNull: true,
    );

    provider.updateProduct(product.id, updatedProduct);

    // ✅ Close loading modal
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      _safelyShowSnackBar(context, l10n.discountRemoved ?? 'Discount removed');
    }
  } catch (e) {
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    if (mounted) {
      _safelyShowSnackBar(context, 'Error removing discount: $e');
    }
  }
}

// ✅ NEW METHOD: Process campaign removal with provider passed explicitly
Future<void> _processRemoveFromCampaignAndDiscountWithProvider(
    BuildContext context, Product product, SellerPanelProvider provider) async {
  final l10n = AppLocalizations.of(context);
  if (!mounted) return;

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
                            colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade400),
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
    final double basePrice = product.originalPrice ?? product.price;
    final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

    await product.reference!.update({
      'price': cleanPrice,
      'discountPercentage': null,
      'originalPrice': null,
      'campaign': null,
      'campaignName': null,
    });

    final updatedProduct = product.copyWith(
      price: cleanPrice,
      setOriginalPriceNull: true,
      setDiscountPercentageNull: true,
      campaign: null,
      campaignName: null,
    );

    provider.updateProduct(product.id, updatedProduct);

    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      _safelyShowSnackBar(context, l10n.removedFromCampaignAndDiscount);
    }
  } catch (e) {
    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    
    if (mounted) {
      _safelyShowSnackBar(context, 'Error removing from campaign: $e');
    }
  }
}

// Add a bulk remove discount function
  Future<void> _processBulkRemoveDiscounts(AppLocalizations l10n) async {
    if (!mounted) return;

    OverlayEntry? loadingOverlay;
    try {
      loadingOverlay = _createLoadingOverlay(
          l10n.removingDiscount ?? 'Removing discounts...');
      Overlay.of(context).insert(loadingOverlay);

      await _removeBulkDiscounts();

      loadingOverlay.remove();
      loadingOverlay = null;

      if (mounted) {
        _safelyShowSnackBar(context, 'All discounts removed successfully');
      }
    } catch (e) {
      debugPrint('Error in bulk remove discount: $e');
      loadingOverlay?.remove();

      if (mounted) {
        _safelyShowSnackBar(context, 'Error removing discounts: $e');
      }
    }
  }

  Future<void> _removeBulkDiscounts() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    if (provider.selectedShop == null) {
      throw Exception('No shop selected');
    }

    final selectedShopId = provider.selectedShop!.id;

    // Get products that currently have discounts
    List<Product> discountedProducts =
        await _getFilteredProductsForBulkOperation(provider, selectedShopId);

    // Filter to only products WITH discounts
    final productsToUpdate = discountedProducts
        .where((product) =>
            product.discountPercentage != null && product.reference != null)
        .toList();

    if (productsToUpdate.isEmpty) {
      throw Exception('No discounted products found to remove discounts from');
    }

    debugPrint('Removing discounts from ${productsToUpdate.length} products');

    // Process in batches
    const int batchSize = 500;
    final int totalBatches = (productsToUpdate.length / batchSize).ceil();

    for (int i = 0; i < totalBatches; i++) {
      final startIndex = i * batchSize;
      final endIndex =
          (startIndex + batchSize).clamp(0, productsToUpdate.length);
      final batchProducts = productsToUpdate.sublist(startIndex, endIndex);

      await _processRemoveBatch(batchProducts, provider, i + 1, totalBatches);

      if (i < totalBatches - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    debugPrint(
        'Successfully removed discounts from ${productsToUpdate.length} products');
  }

  Future<void> _processRemoveBatch(List<Product> products,
      SellerPanelProvider provider, int currentBatch, int totalBatches) async {
    final batch = FirebaseFirestore.instance.batch();
    final List<Product> successfulUpdates = [];

    for (var product in products) {
      try {
        if (product.reference == null) {
          debugPrint('Product ${product.id} has null reference, skipping');
          continue;
        }

        // Use originalPrice if available, otherwise use current price
        final double basePrice = product.originalPrice ?? product.price;
        final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

        batch.update(product.reference!, {
          'price': cleanPrice,
          'discountPercentage': null,
          'originalPrice': null,
        });

        successfulUpdates.add(product);
      } catch (e) {
        debugPrint(
            'Error preparing remove update for product ${product.id}: $e');
      }
    }

    if (successfulUpdates.isEmpty) {
      debugPrint('No valid products in remove batch $currentBatch');
      return;
    }

    try {
      // Commit batch to Firestore
      await batch.commit();

      // Update local state only after successful Firestore commit
      for (var product in successfulUpdates) {
        final double basePrice = product.originalPrice ?? product.price;
        final double cleanPrice = double.parse(basePrice.toStringAsFixed(2));

        // Use the fixed copyWith method with explicit null flags
        final updatedProduct = product.copyWith(
          price: cleanPrice,
          setOriginalPriceNull: true, // Explicitly set to null
          setDiscountPercentageNull: true, // Explicitly set to null
        );

        provider.updateProduct(product.id, updatedProduct);
      }

      debugPrint(
          'Successfully processed remove batch $currentBatch/$totalBatches (${successfulUpdates.length} products)');
    } catch (e) {
      debugPrint('Error committing remove batch $currentBatch: $e');
      throw Exception('Failed to remove discounts in batch $currentBatch: $e');
    }
  }

  Future<void> _removeSalePreference(BuildContext context, Product product) async {
    final l10n = AppLocalizations.of(context);

    try {
      await product.reference!.update({
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

        // Refresh products list
        final provider = Provider.of<SellerPanelProvider>(context, listen: false);
        await provider.initialize();
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
}
