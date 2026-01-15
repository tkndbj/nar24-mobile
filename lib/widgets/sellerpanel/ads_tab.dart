import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../providers/seller_panel_provider.dart';
import '../../widgets/product_card_4.dart';
import '../../models/product.dart';
import 'package:google_fonts/google_fonts.dart';

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

const Color coralColor = Color(0xFFFF7F50);
const Color jadeColor = Color(0xFF00A86B);

class AdsTab extends StatefulWidget {
  const AdsTab({Key? key}) : super(key: key);

  @override
  State<AdsTab> createState() => _AdsTabState();
}

class _AdsTabState extends State<AdsTab> {
  final FocusNode _searchFocusNode = FocusNode();
  late final TextEditingController _searchCtrl;
  late final ScrollController _scrollCtrl;
  bool _showGraph = false;
  Timer? _debounce;
  Timer? _throttle;

  @override
  void initState() {
    super.initState();
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
      if (_throttle?.isActive ?? false) return;
      _throttle = Timer(const Duration(milliseconds: 200), () {
        if (_scrollCtrl.position.pixels >
            _scrollCtrl.position.maxScrollExtent * 0.8) {
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
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _throttle?.cancel();
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Column(
        children: [
          // Search and filter section at the top
          _FilterSection(
            searchFocusNode: _searchFocusNode,
            searchController: _searchCtrl,
          ),
          // Content section with search mode handling
          Expanded(
            child: SafeArea(
              top: false,
              child: Consumer<SellerPanelProvider>(
                builder: (context, provider, _) {
                  // Determine which products to show based on search mode
                  return ValueListenableBuilder<bool>(
                    valueListenable: provider.isSearchingNotifier,
                    builder: (context, isSearching, _) {
                      if (provider.isSearchMode) {
                        return _buildSearchModeContent(
                            context, provider, isSearching);
                      } else {
                        return _buildRegularModeContent(context, provider);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchModeContent(
      BuildContext context, SellerPanelProvider provider, bool isSearching) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isSearching) {
      return _buildShimmerLoading(context, isDark);
    }

    return ValueListenableBuilder<List<Product>>(
      valueListenable: provider.searchResultsNotifier,
      builder: (context, searchResults, _) {
        if (searchResults.isEmpty) {
          return _buildEmptyState(context, l10n.noProductsFound, isDark);
        }

        final boostedProducts =
            searchResults.where((p) => p.isBoosted == true).toList();

        return Column(
          children: [
            // ✅ ALWAYS show action buttons (Home Screen Ads & Analytics always, Graph conditionally)
            _buildActionButtons(context, provider, boostedProducts.isNotEmpty),

            // Only show graph when there are boosted products AND graph is toggled on
            if (boostedProducts.isNotEmpty && _showGraph)
              _buildAnalysisGraph(context, boostedProducts),

            // Search results header
            Container(
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
                    l10n.searchResultsCount(searchResults.length.toString()),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ProductsList(
                products: searchResults,
                scrollController: _scrollCtrl,
                isSearchMode: true,
                isViewer: _isUserViewer(provider.selectedShop),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRegularModeContent(
      BuildContext context, SellerPanelProvider provider) {
    return ValueListenableBuilder<List<Product>>(
      valueListenable: provider.filteredProductsNotifier,
      builder: (context, products, _) {
        final boostedProducts =
            products.where((p) => p.isBoosted == true).toList();

        return Column(
          children: [
            // ✅ ALWAYS show action buttons (Home Screen Ads & Analytics always, Graph conditionally)
            _buildActionButtons(context, provider, boostedProducts.isNotEmpty),

            // Only show graph when there are boosted products AND graph is toggled on
            if (boostedProducts.isNotEmpty && _showGraph)
              _buildAnalysisGraph(context, boostedProducts),

            Expanded(
              child: _ProductsList(
                products: products,
                scrollController: _scrollCtrl,
                isSearchMode: false,
                isViewer: _isUserViewer(provider.selectedShop),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildShimmerLoading(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 120,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty-product.png',
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
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    SellerPanelProvider provider,
    bool hasBoostedProducts,
  ) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          // First row: Home Screen Ads and Analytics (ALWAYS visible)
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  context,
                  l10n.homeScreenAds,
                  Icons.home_outlined,
                  () {
                    final shopId = provider.selectedShop?.id;

                    // ✅ Extract shopName from DocumentSnapshot data
                    final shopData =
                        provider.selectedShop?.data() as Map<String, dynamic>?;
                    final shopName = shopData?['name'] as String?;

                    if (shopId != null && shopName != null) {
                      context.push(
                        '/seller-panel/ads_screen',
                        extra: {
                          'shopId': shopId,
                          'shopName': shopName,
                        },
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.noShopSelected,
                            style: const TextStyle(fontFamily: 'Figtree'),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  context,
                  l10n.analytics,
                  Icons.analytics_outlined,
                  () {
                    final shopId = provider.selectedShop?.id;
                    if (shopId != null) {
                      context
                          .push('/seller_panel_ads_analytics_screen/$shopId');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.noShopSelected,
                            style: const TextStyle(fontFamily: 'Figtree'),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),

          // Second row: Graph button (ONLY when shop has boosted products)
          if (hasBoostedProducts) ...[
            const SizedBox(height: 8),
            _buildActionButton(
              context,
              l10n.graph,
              Icons.bar_chart,
              () => setState(() => _showGraph = !_showGraph),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isGraphButton = label == AppLocalizations.of(context).graph;
    final isGraphActive = isGraphButton && _showGraph;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: BorderSide.none, // Remove border since we have gradient
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisGraph(
      BuildContext context, List<dynamic> boostedProducts) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.analysis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: boostedProducts.length,
                itemBuilder: (context, index) {
                  final product = boostedProducts[index];
                  final displayedImpressions =
                      (product.boostedImpressionCount ?? 0) -
                          (product.boostImpressionCountAtStart ?? 0);
                  final displayedClicks = (product.clickCount ?? 0) -
                      (product.boostClickCountAtStart ?? 0);

                  final List<_MetricData> data = [
                    _MetricData(l10n.clicks, displayedClicks),
                    _MetricData(l10n.impressions, displayedImpressions),
                  ];

                  return Container(
                    width: 300,
                    margin: const EdgeInsets.only(right: 16.0),
                    child: _buildSingleItemChart(context, product, data),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleItemChart(
      BuildContext context, dynamic product, List<_MetricData> data) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.productName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: SfCartesianChart(
            primaryXAxis: CategoryAxis(),
            primaryYAxis: NumericAxis(),
            legend: Legend(isVisible: true),
            tooltipBehavior: TooltipBehavior(enable: true),
            series: <CartesianSeries<_MetricData, String>>[
              ColumnSeries<_MetricData, String>(
                name: l10n.clicks,
                dataSource: data
                    .where((metric) => metric.label == l10n.clicks)
                    .toList(),
                xValueMapper: (metric, _) => metric.label,
                yValueMapper: (metric, _) => metric.value,
                color: jadeColor,
                dataLabelSettings: const DataLabelSettings(isVisible: true),
              ),
              ColumnSeries<_MetricData, String>(
                name: l10n.impressions,
                dataSource: data
                    .where((metric) => metric.label == l10n.impressions)
                    .toList(),
                xValueMapper: (metric, _) => metric.label,
                yValueMapper: (metric, _) => metric.value,
                color: coralColor,
                dataLabelSettings: const DataLabelSettings(isVisible: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Separate widget for filter section to avoid unnecessary rebuilds
class _FilterSection extends StatelessWidget {
  final FocusNode searchFocusNode;
  final TextEditingController searchController;

  const _FilterSection({
    required this.searchFocusNode,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            return Column(
              children: [
                // Enhanced search bar with clear button and search indicator
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
                    focusNode: searchFocusNode,
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
                  // Category filters with Selector optimization
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
                            () => _showCategoryPicker(context),
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
                                        l10n,
                                      )
                                    : l10n.selectSubcategory,
                                () => _showSubcategoryPicker(context),
                                isSelected: selectedSubcategory != null,
                                isSecondary: true,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterButton(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool isSelected = false,
    bool isSecondary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
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
                : null,
            color: !isSelected
                ? (isDark ? const Color(0xFF2A2D3A) : Colors.white)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
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
                isSecondary ? Icons.list_alt_outlined : Icons.category_outlined,
                size: isSecondary ? 14 : 16,
                color: isSelected
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
                    color: isSelected
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
      ),
    );
  }

  void _showCategoryPicker(BuildContext context) {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
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

  void _showSubcategoryPicker(BuildContext context) {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
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

// Separate products list widget with search mode support
class _ProductsList extends StatelessWidget {
  final List<dynamic> products;
  final ScrollController scrollController;
  final bool isSearchMode;
  final bool isViewer;

  const _ProductsList({
    required this.products,
    required this.scrollController,
    required this.isSearchMode,
    this.isViewer = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/empty-product.png',
              width: 150,
              height: 150,
              color: isDark ? Colors.white.withOpacity(0.3) : null,
              colorBlendMode: isDark ? BlendMode.srcATop : null,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noProductsFound,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: products.length,
            separatorBuilder: (context, index) => Divider(
              color: Colors.grey.shade300,
              thickness: 1,
            ),
            itemBuilder: (context, index) {
              final product = products[index];
              return RepaintBoundary(
                child: _ProductItem(
                  key: ValueKey(product.id),
                  product: product,
                  l10n: l10n,
                  isViewer: isViewer,
                ),
              );
            },
          ),
        ),
        // Loading indicator
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
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.tealAccent : Colors.teal,
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
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? Colors.tealAccent : Colors.teal,
                ),
              ),
            ),
          );
        },
      );
    }
  }
}

// Individual product item widget to minimize rebuilds
class _ProductItem extends StatelessWidget {
  final dynamic product;
  final AppLocalizations l10n;
  final bool isViewer;

  const _ProductItem({
    super.key,
    required this.product,
    required this.l10n,
    this.isViewer = false,
  });

  @override
  Widget build(BuildContext context) {
    final isShopProduct = product.shopId != null;
    final isBoosted = product.isBoosted == true && product.boostEndTime != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Row(
        children: [
          Expanded(
            child: ProductCard4(
              imageUrl:
                  (product.imageUrls != null && product.imageUrls.isNotEmpty)
                      ? product.imageUrls.first
                      : '',
              colorImages: (product.colorImages != null)
                  ? Map<String, List<String>>.from(product.colorImages)
                  : <String, List<String>>{},
              productName: product.productName,
              brandModel: product.brandModel ?? '',
              price: (product.price is num)
                  ? (product.price as num).toDouble()
                  : 0.0,
              currency: product.currency,
              productId: product.id,
              isShopProduct: isShopProduct,
            ),
          ),
          const SizedBox(width: 8),
          if (isBoosted)
            _BoostLabel(
              endTime: product.boostEndTime!.toDate(),
              l10n: l10n,
            )
          else if (!isViewer)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: TextButton(
                onPressed: () async {
                  final provider =
                      Provider.of<SellerPanelProvider>(context, listen: false);
                  final shopId = provider.selectedShop?.id;

                  if (shopId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.noShopSelected ?? 'No shop selected',
                          style: const TextStyle(fontFamily: 'Figtree'),
                        ),
                      ),
                    );
                    return;
                  }

                  // ✅ FIXED: Use the correct route with path parameters
                  await context
                      .push('/boost-shop-product/$shopId/${product.id}');

                  // Refresh the single item after boost
                  await provider.updateBoostOnProduct(product.id);
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: const StadiumBorder(),
                  backgroundColor: Colors.transparent,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l10n.boostProduct,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'Figtree',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricData {
  final String label;
  final int value;

  _MetricData(this.label, this.value);
}

class _BoostLabel extends StatefulWidget {
  final DateTime endTime;
  final AppLocalizations l10n;

  const _BoostLabel({required this.endTime, required this.l10n});

  @override
  State<_BoostLabel> createState() => _BoostLabelState();
}

class _BoostLabelState extends State<_BoostLabel> {
  late Timer _timer;
  late Duration _remainingTime;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.endTime.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingTime = widget.endTime.difference(DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remainingTime == Duration.zero) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: const Color(0xFF00A86B)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${widget.l10n.boosted}: $_formatted',
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'Figtree',
          color: Color(0xFF00A86B),
        ),
      ),
    );
  }

  String get _formatted {
    final h = _remainingTime.inHours.toString().padLeft(2, '0');
    final m = (_remainingTime.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remainingTime.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
