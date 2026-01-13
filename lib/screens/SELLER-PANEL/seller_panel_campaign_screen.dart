import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import '../../models/product.dart';
import 'package:flutter/services.dart';
import 'seller_panel_campaign_discount_screen.dart';

class SellerPanelCampaignScreen extends StatefulWidget {
  final Map<String, dynamic> campaign;

  const SellerPanelCampaignScreen({
    super.key,
    required this.campaign,
  });

  @override
  State<SellerPanelCampaignScreen> createState() =>
      _SellerPanelCampaignScreenState();
}

class _SellerPanelCampaignScreenState extends State<SellerPanelCampaignScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedProductIds = <String>{};

  late AnimationController _fabAnimationController;
  late AnimationController _fabPulseController;
  late Animation<double> _fabScaleAnimation;
  late Animation<Offset> _fabSlideAnimation;
  late Animation<double> _fabPulseAnimation;

  bool _isSearching = false;
  String _searchQuery = '';
  List<Product> _filteredProducts = [];
  bool _isLoadingMore = false;

  // Modern color scheme
  static const Color _primaryBlue = Color(0xFF1B73E8);
  static const Color _surfaceColor = Color(0xFFFAFBFC);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE8EAED);
  static const Color _textPrimary = Color(0xFF202124);
  static const Color _textSecondary = Color(0xFF5F6368);
  static const Color _successGreen = Color(0xFF137333);
  static const Color _warningOrange = Color(0xFFEA8600);
  static const Color _jadeGreen = Color(0xFF00A86B);
  static const Color _darkBackground = Color(0xFF1C1A29);
  static const Color _darkCard = Color.fromARGB(255, 33, 31, 49);

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fabPulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fabScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.elasticOut,
    ));

    _fabSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeOutBack,
    ));

    _fabPulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _fabPulseController,
      curve: Curves.easeInOut,
    ));

    // Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);

    // Load initial products
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _fabAnimationController.dispose();
    _fabPulseController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadProducts() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    await provider.fetchStockProducts(shopId: provider.selectedShop?.id);
    _updateFilteredProducts();
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    await provider.fetchNextStockPage(shopId: provider.selectedShop?.id);

    setState(() => _isLoadingMore = false);
    _updateFilteredProducts();
  }

  void _updateFilteredProducts() {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final allProducts = provider.filteredProducts;

    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(allProducts);
    } else {
      _filteredProducts = allProducts.where((product) {
        return product.productName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            (product.brandModel?.toLowerCase() ?? '')
                .contains(_searchQuery.toLowerCase()) ||
            (product.category ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Update FAB animation based on selection
    if (_selectedProductIds.isNotEmpty &&
        !_fabAnimationController.isCompleted) {
      _fabAnimationController.forward();
      _fabPulseController.repeat(reverse: true);
    } else if (_selectedProductIds.isEmpty &&
        _fabAnimationController.isCompleted) {
      _fabAnimationController.reverse();
      _fabPulseController.stop();
      _fabPulseController.reset();
    }

    setState(() {});
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;
    });
    _updateFilteredProducts();
  }

  void _toggleProductSelection(String productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
    _updateFilteredProducts();

    // Haptic feedback
    HapticFeedback.selectionClick();
  }

  void _selectAllVisible() {
    setState(() {
      for (final product in _filteredProducts) {
        _selectedProductIds.add(product.id);
      }
    });
    _updateFilteredProducts();
    HapticFeedback.mediumImpact();
  }

  void _clearSelection() {
    setState(() {
      _selectedProductIds.clear();
    });
    _updateFilteredProducts();
    HapticFeedback.lightImpact();
  }

  void _navigateToDiscountScreen() {
    final l10n = AppLocalizations.of(context);

    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(l10n.selectAtLeastOneProduct),
            ],
          ),
          backgroundColor: _warningOrange,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
      return;
    }

    final selectedProducts = _filteredProducts
        .where((product) => _selectedProductIds.contains(product.id))
        .toList();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SellerPanelCampaignDiscountScreen(
          campaign: widget.campaign,
          selectedProducts: selectedProducts,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.ease;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      // 2) overall background
      backgroundColor: dark ? _darkBackground : _surfaceColor,
      appBar: _buildAppBar(l10n),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildSearchSection(l10n),
            _buildSelectionHeader(l10n),
            Expanded(child: _buildProductList(l10n)),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(l10n),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      elevation: 0,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? _darkBackground
          : _cardColor,
      // 1) pop-back icon color
      iconTheme: IconThemeData(
        color: dark ? Colors.white : _textPrimary,
      ),
      foregroundColor: dark ? Colors.white : _textPrimary,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios,
            size: 18, color: dark ? Colors.white : null),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.selectProducts,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: dark ? Colors.white : _textPrimary,
            ),
          ),
          Text(
            widget.campaign['title'] ?? l10n.campaign,
            style: TextStyle(
              fontSize: 12,
              color: _textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _borderColor.withOpacity(0.1),
                _borderColor,
                _borderColor.withOpacity(0.1)
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection(AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: dark ? _darkCard : _cardColor,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? _darkCard : _surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isSearching ? _primaryBlue.withOpacity(0.3) : _borderColor,
            width: 1.5,
          ),
          boxShadow: _isSearching
              ? [
                  BoxShadow(
                    color: _primaryBlue.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(
            color: dark ? Colors.white : _textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: l10n.searchProductsBrandsCategories,
            hintStyle: TextStyle(
              color: dark ? Colors.white70 : _textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Container(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.search_rounded,
                color: _isSearching ? _primaryBlue : _textSecondary,
                size: 20,
              ),
            ),
            suffixIcon: _isSearching
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: _textSecondary,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHeader(AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: dark ? _darkBackground : _cardColor,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dark ? _darkBackground : _surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
            ),
            child: Text(
              l10n.productsCount(_filteredProducts.length),
              style: TextStyle(
                color: dark ? Colors.white : _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (_selectedProductIds.isNotEmpty) ...[
            _buildActionButton(
              icon: Icons.clear_all_rounded,
              label: l10n.clear,
              onPressed: _clearSelection,
              color: dark ? Colors.white : _textSecondary,
            ),
            const SizedBox(width: 10),
          ],
          _buildActionButton(
            icon: Icons.done_all_rounded,
            label: l10n.selectAll,
            onPressed: _selectAllVisible,
            color: _primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductList(AppLocalizations l10n) {
    return Consumer<SellerPanelProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingStock && _filteredProducts.isEmpty) {
          return _buildLoadingList();
        }

        if (_filteredProducts.isEmpty) {
          return _buildEmptyState(l10n);
        }

        return RefreshIndicator(
          onRefresh: _loadProducts,
          color: _primaryBlue,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: _filteredProducts.length + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index < _filteredProducts.length) {
                return _buildProductCard(_filteredProducts[index], l10n);
              }
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: _primaryBlue,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProductCard(Product product, AppLocalizations l10n) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedProductIds.contains(product.id);
    final isOutOfStock = product.quantity == 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: dark ? _darkCard : _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _jadeGreen : _borderColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleProductSelection(product.id),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product Image
                Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _surfaceColor,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: product.imageUrls.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: product.imageUrls.first,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: _surfaceColor,
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: _primaryBlue,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: _surfaceColor,
                                  child: Icon(
                                    Icons.image_not_supported_rounded,
                                    color: _textSecondary,
                                    size: 24,
                                  ),
                                ),
                              )
                            : Container(
                                color: _surfaceColor,
                                child: Icon(
                                  Icons.inventory_2_rounded,
                                  color: _textSecondary,
                                  size: 24,
                                ),
                              ),
                      ),
                    ),
                    // Out of stock overlay
                    if (isOutOfStock)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n.outOfStock,
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: dark ? Colors.white : _textPrimary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          text: product.price.toStringAsFixed(2),
                          style: TextStyle(
                            color: _warningOrange,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: ' ${product.currency ?? 'TL'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _warningOrange.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_rounded,
                                  size: 12,
                                  color: _textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${product.quantity}',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Selection indicator
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? _jadeGreen : _cardColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? _jadeGreen : _borderColor,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  )
                                : null,
                          ),
                        ],
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

  Widget _buildLoadingList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildSkeletonCard(),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 70,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 50,
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(5),
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

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _surfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                _isSearching
                    ? Icons.search_off_rounded
                    : Icons.inventory_2_rounded,
                size: 40,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isSearching ? l10n.noProductsFound : l10n.noProductsAvailable,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSearching
                  ? l10n.tryAdjustingSearchTerms
                  : l10n.addProductsToShop,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (_isSearching) ...[
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _primaryBlue.withOpacity(0.3)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.clear_rounded,
                            color: _primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.clearSearch,
                            style: TextStyle(
                              color: _primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(AppLocalizations l10n) {
    return AnimatedBuilder(
      animation:
          Listenable.merge([_fabAnimationController, _fabPulseController]),
      builder: (context, child) {
        return SlideTransition(
          position: _fabSlideAnimation,
          child: ScaleTransition(
            scale: _fabScaleAnimation,
            child: AnimatedBuilder(
              animation: _fabPulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _fabPulseAnimation.value,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FloatingActionButton.extended(
                        onPressed: _navigateToDiscountScreen,
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          l10n.continueWithProducts(_selectedProductIds.length),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
