import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import '../product_card_4.dart';
import '../../constants/all_in_one_category_data.dart';
import 'package:google_fonts/google_fonts.dart';
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

// Pre-computed static color maps
const Map<String, Color> _colorNameToColor = {
  'blue': Colors.blue,
  'orange': Colors.orange,
  'yellow': Colors.yellow,
  'black': Colors.black,
  'brown': Colors.brown,
  'dark blue': Colors.blueAccent,
  'gray': Colors.grey,
  'pink': Colors.pink,
  'red': Colors.red,
  'white': Colors.white,
  'green': Colors.green,
  'purple': Colors.purple,
  'teal': Colors.teal,
  'lime': Colors.lime,
  'cyan': Colors.cyan,
  'magenta': Colors.pinkAccent,
  'indigo': Colors.indigo,
  'amber': Colors.amber,
  'deep orange': Colors.deepOrange,
  'light blue': Colors.lightBlue,
  'deep purple': Colors.deepPurple,
  'light green': Colors.lightGreen,
  'dark gray': Colors.blueGrey,
  'beige': Color.fromRGBO(188, 170, 164, 1),
  'turquoise': Colors.tealAccent,
  'violet': Colors.purpleAccent,
  'olive': Color.fromRGBO(85, 139, 47, 1),
  'maroon': Color.fromRGBO(136, 14, 79, 1),
  'navy': Color.fromRGBO(21, 40, 77, 1),
  'silver': Color.fromRGBO(207, 216, 220, 1),
};

/// Displays the quantity stock details for the shop's products.
class StockTab extends StatefulWidget {
  const StockTab({Key? key}) : super(key: key);

  @override
  _StockTabState createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> with TickerProviderStateMixin {
  late FocusNode _searchFocusNode;
  late TextEditingController _searchController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _outOfStock = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  Timer? _throttle;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchController = TextEditingController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Search functionality - same pattern as ProductsTab
    _searchController.addListener(() {
      final provider = context.read<SellerPanelProvider>();

      // Immediate UI feedback - show that search is starting
      if (_searchController.text.trim().isNotEmpty && !provider.isSearchMode) {
        provider.setSearchModeImmediate(true);
      } else if (_searchController.text.trim().isEmpty &&
          provider.isSearchMode) {
        provider.setSearchModeImmediate(false);
      }

      // Debounced search execution
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          provider.setSearchQuery(_searchController.text);
        }
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SellerPanelProvider>();

      // Only fetch if not already loading and shop is selected
      if (!provider.isLoadingStock && provider.selectedShop != null) {
        provider.fetchStockProducts(shopId: provider.selectedShop?.id);
      }

      _fadeController.forward();
    });

    // Scroll listener with search support
    _scrollController.addListener(() {
      if (_throttle?.isActive ?? false) return;
      _throttle = Timer(const Duration(milliseconds: 200), () {
        if (_scrollController.position.pixels >
            _scrollController.position.maxScrollExtent * 0.8) {
          final provider = context.read<SellerPanelProvider>();

          if (provider.isSearchMode) {
            if (!provider.isLoadingMoreSearchResultsNotifier.value &&
                provider.hasMoreSearchResults) {
              provider.loadMoreSearchResults();
            }
          } else {
            provider.fetchNextStockPage();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _throttle?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildSearchResults(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<bool>(
      valueListenable: context.read<SellerPanelProvider>().isSearchingNotifier,
      builder: (context, isSearching, _) {
        if (isSearching) {
          return _buildLoadingState(isDark);
        }

        return ValueListenableBuilder<List<dynamic>>(
          valueListenable:
              context.read<SellerPanelProvider>().searchResultsNotifier,
          builder: (context, searchResults, _) {
            if (searchResults.isEmpty) {
              return _buildEmptyState(l10n.noProductsFound, isDark);
            }
            return _buildProductList(searchResults,
                isSearchMode: true, isDark: isDark);
          },
        );
      },
    );
  }

  Widget _buildRegularProducts(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<List<dynamic>>(
      valueListenable:
          context.read<SellerPanelProvider>().filteredProductsNotifier,
      builder: (context, products, _) {
        if (products.isEmpty) {
          return _buildEmptyState(l10n.noProductsFound, isDark);
        }
        return _buildProductList(products, isSearchMode: false, isDark: isDark);
      },
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 120,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message, bool isDark) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/empty-product.png',
                width: 150,
                height: 150,
                color: isDark ? Colors.white.withOpacity(0.3) : null,
                colorBlendMode: isDark ? BlendMode.srcATop : BlendMode.srcOver,
              ),
              const SizedBox(height: 12),
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

  Widget _buildProductList(List<dynamic> products,
      {required bool isSearchMode, required bool isDark}) {
    final l10n = AppLocalizations.of(context);
    final isViewer = _isUserViewer(context.read<SellerPanelProvider>().selectedShop);

    return CustomScrollView(
      controller: _scrollController,
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
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == products.length) {
                  return _buildLoadingIndicator(isSearchMode, isDark);
                }
                final product = products[index];
                return RepaintBoundary(
                  key: ValueKey(product.id),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200 + (index * 30)),
                    curve: Curves.easeOutBack,
                    child: _ProductRow(
                      key: ValueKey('row_${product.id}'),
                      product: product,
                      index: index,
                      isViewer: isViewer,
                    ),
                  ),
                );
              },
              childCount: products.length + 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(bool isSearchMode, bool isDark) {
    if (isSearchMode) {
      return ValueListenableBuilder<bool>(
        valueListenable: context
            .read<SellerPanelProvider>()
            .isLoadingMoreSearchResultsNotifier,
        builder: (context, isLoadingMoreSearch, _) {
          if (!isLoadingMoreSearch) {
            return const SizedBox.shrink();
          }
          return Container(
            margin: const EdgeInsets.all(8),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.tealAccent : Colors.teal,
                ),
                strokeWidth: 3,
              ),
            ),
          );
        },
      );
    } else {
      return ValueListenableBuilder<bool>(
        valueListenable:
            context.read<SellerPanelProvider>().isFetchingMoreProductsNotifier,
        builder: (context, isFetching, _) {
          return isFetching
              ? Container(
                  margin: const EdgeInsets.all(8),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.tealAccent : Colors.teal,
                      ),
                      strokeWidth: 3,
                    ),
                  ),
                )
              : const SizedBox.shrink();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color.fromARGB(255, 244, 244, 244)
              : Color(0xFF1C1A29),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // Compact Header Section
              Container(
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
                      color: isDark
                          ? Colors.black26
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Consumer<SellerPanelProvider>(
                  builder: (context, provider, child) {
                    return Column(
                      children: [
                        _SearchBar(
                          searchFocusNode: _searchFocusNode,
                          searchController: _searchController,
                        ),
                        const SizedBox(height: 8),
                        // Only show filters when NOT in search mode
                        if (!provider.isSearchMode) const _FilterRow(),
                      ],
                    );
                  },
                ),
              ),
              // Product list with search support
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Consumer<SellerPanelProvider>(
                    builder: (context, provider, _) {
                      if (provider.isSearchMode) {
                        return _buildSearchResults(context);
                      } else {
                        return _buildRegularProducts(context);
                      }
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

// Enhanced SearchBar widget with search indicator
class _SearchBar extends StatelessWidget {
  final FocusNode searchFocusNode;
  final TextEditingController searchController;

  const _SearchBar({
    required this.searchFocusNode,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        focusNode: searchFocusNode,
        controller: searchController,
        style: TextStyle(
          fontSize: 14,
          fontFamily: 'Figtree',
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
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  ),
                ),
          hintText: l10n.searchProducts,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          filled: true,
          fillColor: isDark ? const Color(0xFF2A2D3A) : Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
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
    );
  }
}

// Compact FilterRow widget with ValueNotifier optimization
class _FilterRow extends StatelessWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: provider.stockCategoryNotifier,
                  builder: (context, category, _) {
                    return _buildModernFilterChip(
                      context,
                      category != null
                          ? AllInOneCategoryData.localizeCategoryKey(
                              category, l10n)
                          : l10n.selectCategory,
                      () => _showCategoryPicker(context, provider),
                      isSelected: category != null,
                      icon: Icons.category_outlined,
                    );
                  },
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: provider.stockCategoryNotifier,
                  builder: (context, category, _) {
                    if (category == null) return const SizedBox.shrink();
                    return Row(
                      children: [
                        const SizedBox(width: 8),
                        ValueListenableBuilder<String?>(
                          valueListenable: provider.stockSubcategoryNotifier,
                          builder: (context, subcategory, _) {
                            return _buildModernFilterChip(
                              context,
                              subcategory != null
                                  ? AllInOneCategoryData.localizeSubcategoryKey(
                                      category, subcategory, l10n)
                                  : l10n.selectSubcategory,
                              () => _showSubcategoryPicker(context, provider),
                              isSelected: subcategory != null,
                              icon: Icons.list_alt_outlined,
                              isSecondary: true,
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        const _OutOfStockButton(),
      ],
    );
  }

  Widget _buildModernFilterChip(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool isSelected = false,
    IconData? icon,
    bool isSecondary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSecondary ? 8 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.teal.shade400 : Colors.teal)
              : (isDark ? const Color(0xFF2A2D3A) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: isSecondary ? 14 : 16,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isSecondary ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                ),
                overflow: TextOverflow.ellipsis,
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
                provider.setStockCategory(null);
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
                  provider.setStockCategory(category['key']);
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
    if (provider.stockCategory == null) return;

    final l10n = AppLocalizations.of(context);
    final subcategories =
        AllInOneCategoryData.kSubcategories[provider.stockCategory] ?? [];
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
                provider.setStockSubcategory(null);
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
                  provider.setStockSubcategory(subcategory);
                  Navigator.pop(context);
                },
                child: Text(
                  AllInOneCategoryData.localizeSubcategoryKey(
                      provider.stockCategory!, subcategory, l10n),
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

// Compact OutOfStockButton widget with ValueNotifier optimization
class _OutOfStockButton extends StatelessWidget {
  const _OutOfStockButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = context.findAncestorStateOfType<_StockTabState>()!;
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);

    return ValueListenableBuilder<bool>(
      valueListenable: provider.stockOutOfStockNotifier,
      builder: (context, outOfStock, _) {
        return GestureDetector(
          onTap: () {
            state.setState(() {
              state._outOfStock = !state._outOfStock;
              provider.setOutOfStockFilter(state._outOfStock);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: outOfStock
                  ? LinearGradient(
                      colors: [
                        Colors.orange.shade400,
                        Colors.deepOrange.shade500
                      ],
                    )
                  : null,
              color: !outOfStock
                  ? (isDark ? const Color(0xFF2A2D3A) : Colors.white)
                  : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: outOfStock
                    ? Colors.orange
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                width: 1,
              ),
            
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: outOfStock
                      ? Colors.white
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.outOfStock,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Compact ProductRow widget
class _ProductRow extends StatelessWidget {
  final dynamic product;
  final int index;
  final bool isViewer;

  const _ProductRow({
    Key? key,
    required this.product,
    required this.index,
    this.isViewer = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isZeroQty = product.quantity == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: isZeroQty
            ? Border.all(
                color: Colors.red.shade400,
                width: 1.5,
              )
            : null,
        
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Card with compact styling
            Container(
              padding: const EdgeInsets.all(8),
              child: ProductCard4(
                imageUrl:
                    (product.imageUrls != null && product.imageUrls.isNotEmpty)
                        ? product.imageUrls.first
                        : '',
                colorImages: (product.colorImages != null)
                    ? Map<String, List<String>>.from(product.colorImages)
                    : <String, List<String>>{},
                productName: product.productName,
                brandModel: product.brandModel,
                price: (product.price is num)
                    ? (product.price as num).toDouble()
                    : 0.0,
                currency: product.currency,
                productId: product.id,
              ),
            ),
            // Quantity section with compact design
            Container(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2D3A) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: isZeroQty
                      ? Border.all(color: Colors.red.shade300, width: 0.8)
                      : null,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isZeroQty
                                    ? Colors.red.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.inventory_rounded,
                                size: 16,
                                color: isZeroQty
                                    ? Colors.red.shade600
                                    : Colors.orange.shade600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.quantity,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${product.quantity}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isZeroQty
                                        ? Colors.red.shade600
                                        : Colors.orange.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _UpdateButton(product: product, color: null, isViewer: isViewer),
                      ],
                    ),
                    if (_hasColorOptions(product)) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 0.8,
                        color: isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade200,
                      ),
                      const SizedBox(height: 8),
                      ..._buildColorOptions(context, product, l10n, isViewer),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasColorOptions(dynamic product) {
    return product.colorQuantities != null &&
        product.colorQuantities is Map &&
        (product.colorQuantities as Map).isNotEmpty;
  }

  List<Widget> _buildColorOptions(
      BuildContext context, dynamic product, AppLocalizations l10n, bool isViewer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Map<dynamic, dynamic> colorQuantities =
        product.colorQuantities as Map<dynamic, dynamic>;

    return colorQuantities.entries.map((entry) {
      final String colorKey = entry.key.toString();
      final int colorQty = entry.value is int ? entry.value as int : 0;
      final isZeroColorQty = colorQty == 0;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: isZeroColorQty
              ? Border.all(color: Colors.red.shade200, width: 0.8)
              : Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _colorNameToColor[colorKey.toLowerCase()] ??
                        Colors.transparent,
                    border: Border.all(
                      color:
                          isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_colorNameToColor[colorKey.toLowerCase()] ??
                                Colors.transparent)
                            .withOpacity(0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedColorName(l10n, colorKey),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isZeroColorQty
                            ? Colors.red.shade600
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$colorQty ${l10n.quantity.toLowerCase()}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _UpdateButton(product: product, color: colorKey, isViewer: isViewer),
          ],
        ),
      );
    }).toList();
  }

  String _localizedColorName(AppLocalizations l10n, String colorName) {
    switch (colorName) {
      case 'Blue':
        return l10n.colorBlue;
      case 'Orange':
        return l10n.colorOrange;
      case 'Yellow':
        return l10n.colorYellow;
      case 'Black':
        return l10n.colorBlack;
      case 'Brown':
        return l10n.colorBrown;
      case 'Dark Blue':
        return l10n.colorDarkBlue;
      case 'Gray':
        return l10n.colorGray;
      case 'Pink':
        return l10n.colorPink;
      case 'Red':
        return l10n.colorRed;
      case 'White':
        return l10n.colorWhite;
      case 'Green':
        return l10n.colorGreen;
      case 'Purple':
        return l10n.colorPurple;
      case 'Teal':
        return l10n.colorTeal;
      case 'Lime':
        return l10n.colorLime;
      case 'Cyan':
        return l10n.colorCyan;
      case 'Magenta':
        return l10n.colorMagenta;
      case 'Indigo':
        return l10n.colorIndigo;
      case 'Amber':
        return l10n.colorAmber;
      case 'Deep Orange':
        return l10n.colorDeepOrange;
      case 'Light Blue':
        return l10n.colorLightBlue;
      case 'Deep Purple':
        return l10n.colorDeepPurple;
      case 'Light Green':
        return l10n.colorLightGreen;
      case 'Dark Gray':
        return l10n.colorDarkGray;
      case 'Beige':
        return l10n.colorBeige;
      case 'Turquoise':
        return l10n.colorTurquoise;
      case 'Violet':
        return l10n.colorViolet;
      case 'Olive':
        return l10n.colorOlive;
      case 'Maroon':
        return l10n.colorMaroon;
      case 'Navy':
        return l10n.colorNavy;
      case 'Silver':
        return l10n.colorSilver;
      default:
        return colorName;
    }
  }
}

// Compact UpdateButton widget with restored modal functionality
class _UpdateButton extends StatelessWidget {
  final dynamic product;
  final String? color;
  final bool isViewer;

  const _UpdateButton({required this.product, this.color, this.isViewer = false});

  @override
  Widget build(BuildContext context) {
    // Hide update button for viewers
    if (isViewer) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: TextButton(
        onPressed: () =>
            _showUpdateDialog(context, l10n, product, color: color),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          backgroundColor: Colors.transparent, // Make background transparent
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          l10n.update,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showUpdateDialog(
      BuildContext context, AppLocalizations l10n, dynamic product,
      {String? color}) {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final TextEditingController controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String placeholderText = l10n.enterNewQuantity;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    showCupertinoModalPopup(
      context: context,
      builder: (dialogContext) {
        final actionSheet = Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
          ),
          child: CupertinoActionSheet(
            title: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.update,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CupertinoTextField(
                    controller: controller,
                    placeholder: placeholderText,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    cursorColor: isDark ? Colors.white : Colors.black,
                    placeholderStyle: TextStyle(
                      color: isDark ? Colors.grey[400]! : Colors.grey,
                      fontSize: 16,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? CupertinoColors.systemGrey5.darkColor
                          : CupertinoColors.systemGrey6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () {
                  final int? newQuantity = int.tryParse(controller.text);
                  if (newQuantity != null) {
                    provider.updateProductQuantity(product.id, newQuantity,
                        color: color);
                    Navigator.of(dialogContext).pop();
                  }
                },
                isDefaultAction: true,
                child: Text(
                  l10n.update,
                  style: TextStyle(
                    color: isDark ? Colors.tealAccent : Colors.teal,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                l10n.cancel,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
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
