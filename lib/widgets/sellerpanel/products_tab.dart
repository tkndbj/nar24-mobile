import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../providers/seller_panel_provider.dart';
import '../../widgets/product_card_4.dart';
import '../../models/product.dart';
import 'dart:async';

/// Checks if the current user is a viewer for the given shop.
bool _isUserViewer(DocumentSnapshot? selectedShop) {
  if (selectedShop == null) return false;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) return false;
  final shopData = selectedShop.data() as Map<String, dynamic>?;
  if (shopData == null) return false;
  final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
  return viewers.contains(currentUserId);
}

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  late final FocusNode _searchFocus;
  late final TextEditingController _searchCtrl;
  late final ScrollController _scrollCtrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchFocus = FocusNode();
    _searchCtrl = TextEditingController();
    _scrollCtrl = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SellerPanelProvider>();
      if (provider.filteredProducts.isEmpty &&
          !provider.isLoadingProducts &&
          provider.selectedShop != null) {
        provider.fetchProducts(shopId: provider.selectedShop!.id);
      }
    });

    // FIXED: More responsive debouncing with immediate state update
    _searchCtrl.addListener(() {
      final provider = context.read<SellerPanelProvider>();

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

    _scrollCtrl.addListener(() {
      // Trigger when we're within ~ one screen height of the bottom
      if (_scrollCtrl.position.extentAfter < 600) {
        final provider = context.read<SellerPanelProvider>();

        if (provider.isSearchMode) {
          if (!provider.isLoadingMoreSearchResultsNotifier.value &&
              provider.hasMoreSearchResults) {
            provider.loadMoreSearchResults();
          }
        } else {
          if (!provider.isFetchingMoreProducts && provider.hasMoreProducts) {
            provider.fetchMoreProducts(shopId: provider.selectedShop?.id);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> switchShop(String newShopId) async {
    final provider = context.read<SellerPanelProvider>();
    await provider.switchShop(newShopId);
    _searchCtrl.clear(); // Clear search when switching shops
    _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _searchFocus.unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color.fromARGB(255, 244, 244, 244)
              : Color(0xFF1C1A29),
        ),
        child: Column(
          children: [
            FilterBar(
              searchFocus: _searchFocus,
              searchController: _searchCtrl,
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: ProductsList(
                  scrollController: _scrollCtrl,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  final FocusNode searchFocus;
  final TextEditingController searchController;

  const FilterBar({
    super.key,
    required this.searchFocus,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.2)
              : Colors.white.withOpacity(0.8),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Consumer<SellerPanelProvider>(
          builder: (context, provider, child) {
            final shopId = provider.selectedShop?.id;
            final hasShop = provider.selectedShop != null;

            return Column(
              children: [
                // ENHANCED: Search Bar with clear button and search indicator
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black26
                            : Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: TextField(
                    focusNode: searchFocus,
                    controller: searchController,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(8),
                        child: ValueListenableBuilder<bool>(
                          valueListenable: provider.isSearchingNotifier,
                          builder: (context, isSearching, _) {
                            if (isSearching) {
                              return SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark ? Colors.tealAccent : Colors.teal,
                                  ),
                                ),
                              );
                            }
                            return Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            );
                          },
                        ),
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                searchController.clear();
                                provider.setSearchQuery('');
                              },
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.clear_rounded,
                                  size: 16,
                                  color: isDark
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade500,
                                ),
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                              ),
                            ),
                      hintText: l10n.searchProducts,
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      filled: true,
                      fillColor:
                          isDark ? const Color(0xFF2A2D3A) : Colors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark ? Colors.tealAccent : Colors.teal,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Filter buttons - only show when NOT in search mode
                if (!provider.isSearchMode) ...[
                  // Category / Subcategory buttons
                  Row(
                    children: [
                      Selector<SellerPanelProvider, String?>(
                        selector: (_, provider) => provider.selectedCategory,
                        builder: (context, selectedCategory, _) {
                          return _buildFilterButton(
                            context,
                            selectedCategory != null
                                ? AllInOneCategoryData.localizeCategoryKey(
                                    selectedCategory, l10n)
                                : l10n.selectCategory,
                            () => _showCategoryPicker(context, provider),
                            isSelected: selectedCategory != null,
                          );
                        },
                      ),
                      Selector<SellerPanelProvider, (String?, String?)>(
                        selector: (_, provider) => (
                          provider.selectedCategory,
                          provider.selectedSubcategory
                        ),
                        builder: (context, data, _) {
                          final (selectedCategory, selectedSubcategory) = data;
                          if (selectedCategory == null)
                            return const SizedBox.shrink();

                          return Row(
                            children: [
                              const SizedBox(width: 8),
                              _buildFilterButton(
                                context,
                                selectedSubcategory != null
                                    ? AllInOneCategoryData
                                        .localizeSubcategoryKey(
                                            selectedCategory,
                                            selectedSubcategory,
                                            l10n)
                                    : l10n.selectSubcategory,
                                () => _showSubcategoryPicker(context, provider),
                                isSelected: selectedSubcategory != null,
                                isSecondary: true,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterButton(
                        context,
                        l10n.productApplications,
                        hasShop
                            ? () => context.push(
                                '/seller_panel_pending_applications/$shopId')
                            : () {},
                        isSelected: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Action buttons - Hide for viewers
                  if (!_isUserViewer(provider.selectedShop))
                    ..._buildActionButtons(context, l10n, hasShop, shopId),
                ] else ...[
                  // Search mode indicator
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // Build action buttons with tablet-responsive layout
  // Tablet: 2 rows x 3 columns, Mobile: 3 rows x 2 columns
  List<Widget> _buildActionButtons(
    BuildContext context,
    AppLocalizations l10n,
    bool hasShop,
    String? shopId,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth >= 600;

    // Define all 6 action buttons
    final listProductButton = _buildFilterButton(
      context,
      l10n.listProduct,
      hasShop
          ? () async {
              final sellerInfoDoc = await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(shopId)
                  .collection('seller_info')
                  .doc('info')
                  .get();

              if (sellerInfoDoc.exists) {
                context.push(
                  '/list-product-shop',
                  extra: {'shopId': shopId},
                );
              } else {
                context.push(
                  '/seller_info',
                  extra: {'shopId': shopId, 'redirectToListProduct': true},
                );
              }
            }
          : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.add_box_rounded,
    );

    final boostProductButton = _buildFilterButton(
      context,
      l10n.boostProduct,
      hasShop ? () => context.push('/boost-shop-products/$shopId') : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.rocket_launch_rounded,
    );

    final applyDiscountButton = _buildFilterButton(
      context,
      l10n.applyDiscount,
      hasShop ? () => context.push('/seller_panel_discount_screen') : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.local_offer_rounded,
    );

    final createCollectionButton = _buildFilterButton(
      context,
      l10n.createCollection,
      hasShop ? () => context.push('/seller_panel_collection_screen') : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.collections_rounded,
    );

    final createBundleButton = _buildFilterButton(
      context,
      l10n.createBundle,
      hasShop ? () => context.push('/seller_panel_bundle_screen') : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.inventory_2_rounded,
    );

    final archivedButton = _buildFilterButton(
      context,
      l10n.archived,
      hasShop ? () => context.push('/seller_panel_archived_screen') : () {},
      isSelected: false,
      isActionButton: true,
      actionIcon: Icons.archive_rounded,
    );

    if (isTablet) {
      // Tablet layout: 2 rows x 3 columns
      return [
        Row(
          children: [
            Expanded(child: listProductButton),
            const SizedBox(width: 8),
            Expanded(child: boostProductButton),
            const SizedBox(width: 8),
            Expanded(child: applyDiscountButton),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: createCollectionButton),
            const SizedBox(width: 8),
            Expanded(child: createBundleButton),
            const SizedBox(width: 8),
            Expanded(child: archivedButton),
          ],
        ),
      ];
    } else {
      // Mobile layout: 3 rows x 2 columns
      return [
        Row(
          children: [
            Expanded(child: listProductButton),
            const SizedBox(width: 8),
            Expanded(child: boostProductButton),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: applyDiscountButton),
            const SizedBox(width: 8),
            Expanded(child: createCollectionButton),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: createBundleButton),
            const SizedBox(width: 8),
            Expanded(child: archivedButton),
          ],
        ),
      ];
    }
  }

  Widget _buildFilterButton(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool isSelected = false,
    bool isSecondary = false,
    bool isActionButton = false,
    IconData? actionIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSecondary ? 8 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: isDark
                      ? [Colors.tealAccent.shade400, Colors.teal.shade600]
                      : [Colors.teal.shade400, Colors.teal.shade600],
                )
              : (isActionButton
                  ? const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    )
                  : null),
          color: !isSelected && !isActionButton
              ? (isDark ? const Color(0xFF2A2D3A) : Colors.white)
              : null,
          borderRadius: BorderRadius.circular(8),
          border: isActionButton
              ? null // No border for action buttons
              : Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActionButton && actionIcon != null
                  ? actionIcon
                  : (isSecondary
                      ? Icons.list_alt_outlined
                      : Icons.category_outlined),
              size: isSecondary ? 14 : 16,
              color: isActionButton || isSelected
                  ? Colors.white
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: isSecondary ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: isActionButton || isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker(BuildContext context, SellerPanelProvider provider) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final actionSheet = CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                provider.setCategory(null);
                Navigator.pop(context);
              },
              child: Text(
                l10n.none,
                style: GoogleFonts.inter(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
              ),
            ),
            ...AllInOneCategoryData.kCategories.map((category) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  provider.setCategory(category['key']);
                  Navigator.pop(context);
                },
                child: Text(
                  AllInOneCategoryData.localizeCategoryKey(
                      category['key']!, l10n),
                  style: GoogleFonts.inter(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.inter(
                color: isDarkMode ? Colors.white : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

        // Tablet: half width and centered at bottom
        if (isTablet) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.5),
              child: actionSheet,
            ),
          );
        }
        return actionSheet;
      },
    );
  }

  void _showSubcategoryPicker(
      BuildContext context, SellerPanelProvider provider) {
    if (provider.selectedCategory == null) return;
    final l10n = AppLocalizations.of(context);
    final subcategories =
        AllInOneCategoryData.kSubcategories[provider.selectedCategory] ?? [];
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final actionSheet = CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                provider.setSubcategory(null);
                Navigator.pop(context);
              },
              child: Text(
                l10n.none,
                style: GoogleFonts.inter(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 14,
                ),
              ),
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
                  style: GoogleFonts.inter(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.inter(
                color: isDarkMode ? Colors.white : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

        // Tablet: half width and centered at bottom
        if (isTablet) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.5),
              child: actionSheet,
            ),
          );
        }
        return actionSheet;
      },
    );
  }
}

class ProductsList extends StatelessWidget {
  final ScrollController scrollController;

  const ProductsList({
    super.key,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Selector<SellerPanelProvider, (String?, bool, bool)>(
      selector: (_, provider) => (
        provider.selectedShop?.id,
        provider.isLoadingProducts,
        provider.isSearchMode,
      ),
      builder: (context, data, child) {
        final (shopId, isLoading, isSearchMode) = data;

        if (shopId == null) {
          return Center(
            child: Text(
              l10n.pleaseSelectShop,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          );
        }

        if (isLoading && !isSearchMode) {
          return _buildShimmerGrid(context, isDark);
        }

        return isSearchMode
            ? _buildSearchResults(context)
            : _buildRegularProducts(context);
      },
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<bool>(
      valueListenable: context.read<SellerPanelProvider>().isSearchingNotifier,
      builder: (context, isSearching, _) {
        if (isSearching) {
          return _buildShimmerGrid(context, isDark);
        }

        return ValueListenableBuilder<List<Product>>(
          valueListenable:
              context.read<SellerPanelProvider>().searchResultsNotifier,
          builder: (context, searchResults, _) {
            if (searchResults.isEmpty) {
              return _buildEmptyState(context, l10n.noProductsFound, isDark);
            }

            return _buildProductGrid(context, searchResults,
                isSearchMode: true);
          },
        );
      },
    );
  }

  Widget _buildRegularProducts(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<List<Product>>(
      valueListenable:
          context.read<SellerPanelProvider>().filteredProductsNotifier,
      builder: (context, filteredProducts, _) {
        if (filteredProducts.isEmpty) {
          return _buildEmptyState(context, l10n.noProductsFound, isDark);
        }

        return _buildProductGrid(context, filteredProducts,
            isSearchMode: false);
      },
    );
  }

  Widget _buildShimmerGrid(BuildContext context, bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
                childCount: 6, // Show 6 shimmer items
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, bool isDark) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image(
                image: const AssetImage('assets/images/empty-product.png'),
                width: 150,
                height: 150,
                color: isDark ? Colors.white.withOpacity(0.3) : null,
                colorBlendMode: isDark ? BlendMode.srcATop : null,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid(BuildContext context, List<Product> products,
      {required bool isSearchMode}) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const jadeGreen = Color(0xFF00A86B);
    final isViewer =
        _isUserViewer(context.read<SellerPanelProvider>().selectedShop);

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // Search results header
        if (isSearchMode) ...[
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (isDark ? Colors.tealAccent : Colors.teal).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isDark ? Colors.tealAccent : Colors.teal)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: isDark ? Colors.tealAccent : Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.searchResultsCount(products.length.toString()),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = products[index];
                final productId = product.id;
                final imageUrl =
                    product.imageUrls.isNotEmpty ? product.imageUrls[0] : '';

                // Use individual RepaintBoundary for each product card
                return RepaintBoundary(
                  key: ValueKey('product_$productId'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: _ProductListItem(
                      product: product,
                      productId: productId,
                      imageUrl: imageUrl,
                      l10n: l10n,
                      isDark: isDark,
                      jadeGreen: jadeGreen,
                      isViewer: isViewer,
                      onPauseProduct: () => _pauseProductWithModal(
                        context,
                        productId,
                        product.productName,
                      ),
                      onDeleteProduct: () => _deleteProductWithModal(
                        context,
                        productId,
                        product.productName,
                      ),
                    ),
                  ),
                );
              },
              childCount: products.length,
              // Add find/remove optimizations
              findChildIndexCallback: (Key key) {
                if (key is ValueKey<String>) {
                  final valueKey = key.value;
                  if (valueKey.startsWith('product_')) {
                    final productId = valueKey.substring(8);
                    final index = products.indexWhere((p) => p.id == productId);
                    return index >= 0 ? index : null;
                  }
                }
                return null;
              },
            ),
          ),
        ),
        _buildLoadingIndicator(context, isSearchMode, isDark),
      ],
    );
  }

  Widget _buildLoadingIndicator(
      BuildContext context, bool isSearchMode, bool isDark) {
    if (isSearchMode) {
      return ValueListenableBuilder<bool>(
        valueListenable: context
            .read<SellerPanelProvider>()
            .isLoadingMoreSearchResultsNotifier,
        builder: (context, isLoadingMoreSearch, _) {
          if (!isLoadingMoreSearch) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.tealAccent : Colors.teal,
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      return ValueListenableBuilder<bool>(
        valueListenable:
            context.read<SellerPanelProvider>().isFetchingMoreProductsNotifier,
        builder: (context, isFetchingMore, _) {
          if (!isFetchingMore) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.tealAccent : Colors.teal,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _pauseProductWithModal(
      BuildContext context, String productId, String productName) async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await _showPauseConfirmation(context, productName);
    if (!confirmed) return;

    if (!context.mounted) return;

    // ✅ CAPTURE the dialog context
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx; // ← Save the dialog's context
        return Dialog(
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
                            colors: [Colors.orange, Colors.deepOrange],
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.archive_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.archivingProduct ?? 'Archiving product...',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  productName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.orange),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final provider = context.read<SellerPanelProvider>();
      await provider.toggleProductPauseStatus(productId, true);

      // ✅ Use the captured dialog context to close ONLY the dialog
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (context.mounted) {
        final currentFiltered = provider.filteredProductsNotifier.value;
        provider.filteredProductsNotifier.value =
            currentFiltered.where((p) => p.id != productId).toList();

        if (provider.isSearchMode) {
          final currentSearch = provider.searchResultsNotifier.value;
          provider.searchResultsNotifier.value =
              currentSearch.where((p) => p.id != productId).toList();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l10n.productArchivedSuccess ??
                        'Product has been successfully archived')),
              ],
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(l10n.productArchiveError ??
                        'Failed to archive product. Please try again.')),
              ],
            ),
            backgroundColor: Colors.red.shade500,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<bool> _showPauseConfirmation(
      BuildContext context, String productName) async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.archive_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.archiveProduct ?? 'Archive Product',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.archiveProductConfirmation ??
                                  'This product will be moved to archived products and become unavailable for sale.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        color: Colors.orange,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.archive_rounded,
                                size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              l10n.archive ?? 'Archive',
                              style: const TextStyle(
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
    );

    return result ?? false;
  }

  void _showPauseLoadingModal(BuildContext context, String productName) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                          colors: [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.archive_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                l10n.archivingProduct ?? 'Archiving product...',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                productName,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
                            const AlwaysStoppedAnimation<Color>(Colors.orange),
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

  Future<void> _deleteProductWithModal(
      BuildContext context, String productId, String productName) async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await _showDeleteConfirmation(context, productName);
    if (!confirmed) return;

    if (!context.mounted) return;

    // ✅ CAPTURE the dialog context
    BuildContext? dialogContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        dialogContext = ctx; // ← Save the dialog's context
        return Dialog(
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
                  l10n.deletingProduct ?? 'Deleting product...',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  productName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
        );
      },
    );

    try {
      final provider = context.read<SellerPanelProvider>();
      await provider.removeProduct(productId);

      // ✅ Use the captured dialog context
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (context.mounted) {
        final currentFiltered = provider.filteredProductsNotifier.value;
        provider.filteredProductsNotifier.value =
            currentFiltered.where((p) => p.id != productId).toList();

        if (provider.isSearchMode) {
          final currentSearch = provider.searchResultsNotifier.value;
          provider.searchResultsNotifier.value =
              currentSearch.where((p) => p.id != productId).toList();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.productDeletedSuccess ??
                      'Product has been successfully deleted'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.productDeleteError ??
                      'Failed to delete product. Please try again.'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmation(
      BuildContext context, String productName) async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.redAccent],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.deleteProduct ?? 'Delete Product',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.deleteProductConfirmation ??
                                  'This action cannot be undone. The product will be permanently deleted.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        color: Colors.red,
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.delete_forever_rounded,
                                size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              l10n.delete ?? 'Delete',
                              style: const TextStyle(
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
    );

    return result ?? false;
  }

  void _showDeleteLoadingModal(BuildContext context, String productName) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                l10n.deletingProduct ?? 'Deleting product...',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                productName,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

class _ProductListItem extends StatelessWidget {
  final Product product;
  final String productId;
  final String imageUrl;
  final AppLocalizations l10n;
  final bool isDark;
  final Color jadeGreen;
  final VoidCallback onPauseProduct;
  final VoidCallback onDeleteProduct;
  final bool isViewer;

  const _ProductListItem({
    required this.product,
    required this.productId,
    required this.imageUrl,
    required this.l10n,
    required this.isDark,
    required this.jadeGreen,
    required this.onPauseProduct,
    required this.onDeleteProduct,
    this.isViewer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey[200]!,
            blurRadius: 6,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  context.push(
                    '/seller_panel_product_detail',
                    extra: {'product': product, 'productId': productId},
                  );
                },
                child: ProductCard4(
                  key: ValueKey(productId),
                  imageUrl: imageUrl,
                  colorImages: product.colorImages,
                  selectedColor: null,
                  productName: product.productName.isNotEmpty
                      ? product.productName
                      : l10n.unnamedProduct,
                  brandModel: product.brandModel ?? '',
                  price: product.price,
                  currency: product.currency,
                  averageRating: product.averageRating,
                  productId: productId,
                  originalPrice: product.originalPrice,
                  discountPercentage: product.discountPercentage,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Hide action buttons for viewers
            if (!isViewer)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ProductActionButton(
                    label: product.paused == true
                        ? l10n.resumeSale
                        : l10n.pauseSale,
                    onPressed: product.paused == true
                        ? () async {
                            try {
                              await context
                                  .read<SellerPanelProvider>()
                                  .toggleProductPauseStatus(productId, false);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Failed to update product status'),
                                  ),
                                );
                              }
                            }
                          }
                        : onPauseProduct,
                    jadeGreen: jadeGreen,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  _ProductActionButton(
                    label: l10n.removeProduct,
                    onPressed: onDeleteProduct,
                    jadeGreen: jadeGreen,
                    isDark: isDark,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Extract button to its own widget for better performance
class _ProductActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color jadeGreen;
  final bool isDark;

  const _ProductActionButton({
    required this.label,
    required this.onPressed,
    required this.jadeGreen,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: const StadiumBorder(),
          backgroundColor: Colors.transparent,
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
