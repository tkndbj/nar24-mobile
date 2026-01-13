import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/product.dart';
import '../../models/bundle.dart';
import '../../providers/seller_panel_provider.dart';
import '../../generated/l10n/app_localizations.dart';

class SellerPanelCreateBundleScreen extends StatefulWidget {
  const SellerPanelCreateBundleScreen({super.key});

  @override
  State<SellerPanelCreateBundleScreen> createState() =>
      _SellerPanelCreateBundleScreenState();
}

class _SellerPanelCreateBundleScreenState
    extends State<SellerPanelCreateBundleScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bundlePriceController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _bundlePriceFocusNode = FocusNode();

  /// Real-time products listener subscription
  StreamSubscription<QuerySnapshot>? _productsSubscription;

  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  final Map<String, Product> _selectedProducts = {};

  double? _bundlePrice;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasMoreProducts = true;
  DocumentSnapshot? _lastProductDoc;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupProductsListener();
    });
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _searchController.dispose();
    _bundlePriceController.dispose();
    _scrollController.dispose();
    _bundlePriceFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  /// Sets up a real-time listener for shop products
  void _setupProductsListener() {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shopId = provider.selectedShop?.id;

    if (shopId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    // Cancel any existing subscription
    _productsSubscription?.cancel();

    // Set up real-time listener
    _productsSubscription = _firestore
        .collection('shop_products')
        .where('shopId', isEqualTo: shopId)
        .orderBy('createdAt', descending: true)
        .limit(50) // Reasonable limit for real-time updates
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final products = snapshot.docs
            .map((doc) => Product.fromDocument(doc))
            .toList();

        setState(() {
          _availableProducts = products;
          _isLoading = false;
          _hasMoreProducts = snapshot.docs.length >= 50;
          _lastProductDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        });

        _updateFilteredProducts();

        // Update selected products with fresh data
        _refreshSelectedProducts();
      },
      onError: (error) {
        debugPrint('Error listening to products: $error');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );
  }

  /// Refreshes selected products with latest data from listener
  void _refreshSelectedProducts() {
    final updatedSelections = <String, Product>{};
    for (final entry in _selectedProducts.entries) {
      final freshProduct = _availableProducts
          .where((p) => p.id == entry.key)
          .firstOrNull;
      if (freshProduct != null) {
        updatedSelections[entry.key] = freshProduct;
      } else {
        // Keep the old product if not found (might be outside the limit)
        updatedSelections[entry.key] = entry.value;
      }
    }
    _selectedProducts.clear();
    _selectedProducts.addAll(updatedSelections);
  }

  Future<void> _loadAvailableProducts() async {
    // This method is now mainly used for refreshing/reloading
    // The listener handles real-time updates
    _setupProductsListener();
  }

  Future<void> _loadMoreProducts() async {
    if (!_hasMoreProducts || _lastProductDoc == null) return;

    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shopId = provider.selectedShop?.id;

    if (shopId == null) return;

    try {
      Query query = _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastProductDoc!)
          .limit(20);

      final snapshot = await query.get();

      final newProducts =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

      _availableProducts.addAll(newProducts);
      _lastProductDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMoreProducts = snapshot.docs.length == 20;

      _updateFilteredProducts();
    } catch (e) {
      debugPrint('Error loading more products: $e');
    }
  }

  void _updateFilteredProducts() {
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_availableProducts);
    } else {
      _filteredProducts = _availableProducts.where((product) {
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
    setState(() {});
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _updateFilteredProducts();
  }

  void _toggleProductSelection(Product product) {
    setState(() {
      if (_selectedProducts.containsKey(product.id)) {
        _selectedProducts.remove(product.id);
      } else {
        // Max 6 products
        if (_selectedProducts.length >= 6) {
          final l10n = AppLocalizations.of(context);
          _showErrorSnackBar(l10n.maximumProductsPerBundle);
          return;
        }
        _selectedProducts[product.id] = product;
      }

      // Auto-calculate bundle price with 10% discount
      _updateDefaultBundlePrice();
    });
    HapticFeedback.selectionClick();
  }

  void _updateDefaultBundlePrice() {
    if (_selectedProducts.isEmpty) {
      _bundlePrice = null;
      _bundlePriceController.clear();
      return;
    }

    final totalOriginal = _selectedProducts.values
        .fold(0.0, (sum, product) => sum + product.price);

    final defaultPrice = totalOriginal * 0.9; // 10% discount

    _bundlePrice = defaultPrice;
    _bundlePriceController.text = defaultPrice.toStringAsFixed(2);
  }

  void _updateBundlePrice(String value) {
    final price = double.tryParse(value);
    if (price != null && price > 0) {
      setState(() {
        _bundlePrice = price;
      });
    }
  }

  Future<void> _createBundle() async {
    final l10n = AppLocalizations.of(context);

    // Validation
    if (_selectedProducts.length < 2) {
      _showErrorSnackBar(l10n.selectAtLeastTwoProducts);
      return;
    }

    if (_selectedProducts.length > 6) {
      _showErrorSnackBar(l10n.maximumProductsPerBundle);
      return;
    }

    if (_bundlePrice == null || _bundlePrice! <= 0) {
      _showErrorSnackBar(l10n.pleaseEnterValidPrices);
      return;
    }

    final totalOriginal = _selectedProducts.values
        .fold(0.0, (sum, product) => sum + product.price);

    if (_bundlePrice! >= totalOriginal) {
      _showErrorSnackBar(l10n.bundlePriceMustBeLessThanTotal);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);
      final shopId = provider.selectedShop?.id;

      if (shopId == null) throw Exception('No shop selected');

      final batch = _firestore.batch();
      final bundleRef = _firestore.collection('bundles').doc();

      // Calculate discount percentage
      final discountPercentage =
          ((totalOriginal - _bundlePrice!) / totalOriginal * 100);

      // Get currency from first product
      final currency = _selectedProducts.values.first.currency ?? 'TL';

      // Create bundle products list
      final bundleProducts = _selectedProducts.values.map((product) {
        return BundleProduct(
          productId: product.id,
          productName: product.productName,
          originalPrice: product.price,
          imageUrl:
              product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
        );
      }).toList();

      // Create bundle document
      final bundle = Bundle(
        id: bundleRef.id,
        shopId: shopId,
        products: bundleProducts,
        totalBundlePrice: _bundlePrice!,
        totalOriginalPrice: totalOriginal,
        discountPercentage: discountPercentage,
        currency: currency,
        createdAt: DateTime.now(),
        isActive: true,
      );

      batch.set(bundleRef, bundle.toMap());

      // Denormalize: Update each product with bundle info
      for (final productId in _selectedProducts.keys) {
        final productRef =
            _firestore.collection('shop_products').doc(productId);

        // Get other product IDs in this bundle
        final otherProductIds =
            _selectedProducts.keys.where((id) => id != productId).toList();

        batch.update(productRef, {
          'bundleIds': FieldValue.arrayUnion([bundleRef.id]),
          'bundleData': FieldValue.arrayUnion([
            {
              'bundleId': bundleRef.id,
              'bundlePrice': _bundlePrice,
              'bundleDiscount': discountPercentage.round(),
              'bundleProductCount': _selectedProducts.length,
              'otherProductIds': otherProductIds,
            }
          ]),
        });
      }

      await batch.commit();

      _showSuccessSnackBar(l10n.bundleCreatedSuccessfully);
      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      _showErrorSnackBar(l10n.failedToCreateBundleWithError(e.toString()));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _removeSalePreference(Product product) async {
    final l10n = AppLocalizations.of(context);

    try {
      await product.reference!.update({
        'discountThreshold': FieldValue.delete(),
        'bulkDiscountPercentage': FieldValue.delete(),
      });

      if (mounted) {
        _showSuccessSnackBar(l10n.salePreferenceRemovedSuccessfully ??
            'Sale preference removed successfully');
      }

      await _loadAvailableProducts();
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(l10n.errorRemovingSalePreference ??
            'Error removing sale preference: $e');
      }
    }
  }

  double get _totalOriginalPrice {
    return _selectedProducts.values.fold(0.0, (sum, p) => sum + p.price);
  }

  double get _savingsAmount {
    if (_bundlePrice == null) return 0.0;
    return _totalOriginalPrice - _bundlePrice!;
  }

  double get _savingsPercentage {
    if (_bundlePrice == null || _totalOriginalPrice == 0) return 0.0;
    return (_savingsAmount / _totalOriginalPrice * 100);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFE53E3E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF38A169),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_selectedProducts.isNotEmpty) _buildBundleSummary(isDark, l10n),
            _buildSearchBar(l10n, isDark),
            if (_selectedProducts.isNotEmpty) _buildSelectedCount(isDark, l10n),
            Expanded(
              child: _isLoading
                  ? _buildLoadingList(isDark)
                  : _filteredProducts.isEmpty
                      ? _buildEmptyState(l10n.noProductsAvailableForBundle,
                          l10n.addProductsToShopToCreateBundles, isDark)
                      : _buildProductList(isDark, l10n),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(l10n, isDark),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
      foregroundColor: isDark ? Colors.white : const Color(0xFF1A202C),
      title: Text(
        l10n.createBundle,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A202C),
        ),
      ),
      actions: [
        if (_selectedProducts.isNotEmpty)
          TextButton(
            onPressed: () {
              setState(() {
                _selectedProducts.clear();
                _bundlePrice = null;
                _bundlePriceController.clear();
              });
            },
            child: Text(
              l10n.clearAll,
              style: GoogleFonts.figtree(
                color: const Color(0xFFE53E3E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildBundleSummary(bool isDark, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.productsSelectedCount(_selectedProducts.length),
                style: GoogleFonts.figtree(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.originalTotal,
            style: GoogleFonts.figtree(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${_totalOriginalPrice.toStringAsFixed(2)} ${_selectedProducts.values.first.currency ?? 'TL'}',
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.bundlePrice,
            style: GoogleFonts.figtree(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _bundlePriceController,
            focusNode: _bundlePriceFocusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: _updateBundlePrice,
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixText: '${_selectedProducts.values.first.currency ?? 'TL'} ',
              prefixStyle: GoogleFonts.figtree(
                color: Colors.white.withOpacity(0.9),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          if (_bundlePrice != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.saveBundleAmount(
                _savingsAmount.toStringAsFixed(2),
                _selectedProducts.values.first.currency ?? 'TL',
                _savingsPercentage.toStringAsFixed(1),
              ),
              style: GoogleFonts.figtree(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: l10n.searchProducts,
          prefixIcon: const Icon(Icons.search_rounded),
          filled: true,
          fillColor: isDark ? const Color(0xFF2D3748) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF667EEA),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCount(bool isDark, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF38A169).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF38A169).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF38A169),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.productsSelectedOutOfSix(_selectedProducts.length),
            style: GoogleFonts.figtree(
              color: const Color(0xFF38A169),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(bool isDark, AppLocalizations l10n) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final isSelected = _selectedProducts.containsKey(product.id);

        return _buildProductCard(product, isSelected, isDark, l10n);
      },
    );
  }

  Widget _buildProductCard(
      Product product, bool isSelected, bool isDark, AppLocalizations l10n) {
    final hasSalePreference = product.discountThreshold != null &&
        product.bulkDiscountPercentage != null &&
        product.discountThreshold! > 0 &&
        product.bulkDiscountPercentage! > 0;

    final hasDiscount = product.discountPercentage != null &&
        product.discountPercentage! > 0;

    final isBlocked = hasSalePreference || hasDiscount;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
              : [Colors.white, const Color(0xFFFAFBFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF38A169)
              : isDark
                  ? const Color(0xFF4A5568)
                  : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFF38A169).withOpacity(0.15)
                : isDark
                    ? Colors.black.withOpacity(0.15)
                    : const Color(0xFF64748B).withOpacity(0.06),
            blurRadius: isSelected ? 10 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isBlocked
                  ? null
                  : () => _toggleProductSelection(product),
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: isBlocked ? 0.6 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF38A169)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF38A169)
                                : isDark
                                    ? const Color(0xFF4A5568)
                                    : const Color(0xFFCBD5E0),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: isDark
                              ? const Color(0xFF2D3748)
                              : const Color(0xFFF7FAFC),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: product.imageUrls.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: product.imageUrls.first,
                                  fit: BoxFit.cover,
                                )
                              : Icon(
                                  Icons.inventory_2_rounded,
                                  color: isDark
                                      ? const Color(0xFF718096)
                                      : const Color(0xFF94A3B8),
                                  size: 20,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.productName,
                              style: GoogleFonts.figtree(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A202C),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product.price.toStringAsFixed(2)} ${product.currency ?? 'TL'}',
                              style: GoogleFonts.figtree(
                                color: isDark
                                    ? const Color(0xFFA0AAB8)
                                    : const Color(0xFF64748B),
                                fontSize: 12,
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
          ),
          if (hasSalePreference) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.removeSalePreferenceToCreateBundle ??
                          'Remove sale preference to bundle this product',
                      style: GoogleFonts.figtree(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () => _removeSalePreference(product),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n.remove ?? 'Remove',
                        style: GoogleFonts.figtree(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasDiscount && !hasSalePreference) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.percent_rounded,
                    color: Colors.red.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.removeDiscountToCreateBundle,
                      style: GoogleFonts.figtree(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.red.shade300
                            : Colors.red.shade700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n, bool isDark) {
    if (_selectedProducts.length < 2) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _createBundle,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    l10n.createBundleWithCount(_selectedProducts.length),
                    style: GoogleFonts.figtree(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 80,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D3748) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF667EEA).withOpacity(0.1),
                    const Color(0xFF764BA2).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 48,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.figtree(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? const Color(0xFFA0AAB8) : const Color(0xFF4A5568),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.figtree(
                fontSize: 13,
                color:
                    isDark ? const Color(0xFF718096) : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
