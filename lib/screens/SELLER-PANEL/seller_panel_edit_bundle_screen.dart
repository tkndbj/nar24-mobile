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

class SellerPanelEditBundleScreen extends StatefulWidget {
  final Bundle bundle;

  const SellerPanelEditBundleScreen({
    super.key,
    required this.bundle,
  });

  @override
  State<SellerPanelEditBundleScreen> createState() =>
      _SellerPanelEditBundleScreenState();
}

class _SellerPanelEditBundleScreenState
    extends State<SellerPanelEditBundleScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bundlePriceController = TextEditingController();
  final FocusNode _bundlePriceFocusNode = FocusNode();

  late TabController _tabController;

  // Current products in bundle
  Map<String, Product> _currentProducts = {};
  final Set<String> _removedProductIds = {};
  final Set<String> _invalidProductIds = {}; // Track deleted/archived products

  // New products to add
  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  final Map<String, Product> _newSelectedProducts = {};

  double? _bundlePrice;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _autoCleanupPerformed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bundlePrice = widget.bundle.totalBundlePrice;
    _bundlePriceController.text = _bundlePrice!.toStringAsFixed(2);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bundlePriceController.dispose();
    _bundlePriceFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Validate all products in bundle
      await _validateBundleProducts();

      // Auto-cleanup invalid products if any found
      if (_invalidProductIds.isNotEmpty) {
        await _performAutoCleanup();
      }

      // Check if bundle still has minimum products after cleanup
      if (_currentProducts.length < 2) {
        final l10n = AppLocalizations.of(context);
        _showCriticalError(l10n.bundleHasLessThanTwoValidProducts);
        return;
      }

      // Load available products for adding
      await _loadAvailableProducts();
    } catch (e) {
      debugPrint('Error loading data: $e');
      final l10n = AppLocalizations.of(context);
      _showErrorSnackBar(l10n.failedToLoadBundleData(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _validateBundleProducts() async {
    final validProducts = <String, Product>{};
    final invalidIds = <String>{};

    try {
      // Fetch all products in parallel
      final results = await Future.wait(
        widget.bundle.products.map((bp) => _fetchProductSafely(bp.productId)),
        eagerError: false,
      );

      for (var i = 0; i < widget.bundle.products.length; i++) {
        final bundleProduct = widget.bundle.products[i];
        final product = results[i];

        // Check if product exists and is not archived
        if (product == null || product.paused == true) {
          debugPrint(
              '⚠️ Invalid product in bundle: ${bundleProduct.productId} - ${product == null ? "deleted" : "archived"}');
          invalidIds.add(bundleProduct.productId);
        } else {
          validProducts[product.id] = product;
        }
      }

      _currentProducts = validProducts;
      _invalidProductIds.addAll(invalidIds);

      if (invalidIds.isNotEmpty) {
        debugPrint(
            '✅ Filtered out ${invalidIds.length} invalid products from bundle');
      }
    } catch (e) {
      debugPrint('❌ Error validating bundle products: $e');
    }
  }

  Future<Product?> _fetchProductSafely(String productId) async {
    try {
      final doc = await _firestore
          .collection('shop_products')
          .doc(productId)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Product fetch timeout'),
          );

      if (!doc.exists) return null;
      return Product.fromDocument(doc);
    } catch (e) {
      debugPrint('⚠️ Failed to fetch product $productId: $e');
      return null;
    }
  }

  Future<void> _performAutoCleanup() async {
    if (_invalidProductIds.isEmpty || _autoCleanupPerformed) return;

    try {
      _autoCleanupPerformed = true;

      // Step 1: Clean up invalid products using the reliable method
      await Future.wait(
        _invalidProductIds
            .map((id) => _cleanupProductBundleData(id, widget.bundle.id)),
      );

      // Step 2: Update the bundle document
      final validBundleProducts = widget.bundle.products
          .where((bp) => !_invalidProductIds.contains(bp.productId))
          .toList();

      final newTotalOriginal =
          validBundleProducts.fold(0.0, (sum, bp) => sum + bp.originalPrice);
      final currentDiscount = widget.bundle.discountPercentage;
      final newBundlePrice = newTotalOriginal * (1 - currentDiscount / 100);

      await _firestore.collection('bundles').doc(widget.bundle.id).update({
        'products': validBundleProducts.map((bp) => bp.toMap()).toList(),
        'totalOriginalPrice': newTotalOriginal,
        'totalBundlePrice': newBundlePrice,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local state
      _bundlePrice = newBundlePrice;
      _bundlePriceController.text = newBundlePrice.toStringAsFixed(2);
      _hasChanges = false;

      debugPrint(
          '✅ Auto-cleanup completed for ${_invalidProductIds.length} products');
    } catch (e) {
      debugPrint('❌ Auto-cleanup failed: $e');
      final l10n = AppLocalizations.of(context);
      _showErrorSnackBar(l10n.failedToCleanupInvalidProducts(e.toString()));
    }
  }

  Future<void> _loadAvailableProducts() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final shopId = provider.selectedShop?.id;

    if (shopId == null) return;

    try {
      final snapshot = await _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId)
          .where('paused', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      // Filter out products already in bundle
      final existingIds = _currentProducts.keys.toSet();

      _availableProducts = snapshot.docs
          .map((doc) => Product.fromDocument(doc))
          .where((product) => !existingIds.contains(product.id))
          .toList();

      _updateFilteredProducts();
    } catch (e) {
      debugPrint('Error loading products: $e');
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

  void _updateBundlePrice(String value) {
    final price = double.tryParse(value);
    if (price != null && price > 0) {
      setState(() {
        _bundlePrice = price;
        _hasChanges = true;
      });
    }
  }

  void _removeProduct(String productId) {
    setState(() {
      _currentProducts.remove(productId);
      _removedProductIds.add(productId);
      _hasChanges = true;
    });
  }

  void _toggleNewProductSelection(Product product) {
    setState(() {
      if (_newSelectedProducts.containsKey(product.id)) {
        _newSelectedProducts.remove(product.id);
      } else {
        // Check max 6 products total
        if (_currentProducts.length + _newSelectedProducts.length >= 6) {
          final l10n = AppLocalizations.of(context);
          _showErrorSnackBar(l10n.maximumProductsPerBundle);
          return;
        }
        _newSelectedProducts[product.id] = product;
      }
      _hasChanges = true;
    });
  }

  double get _totalOriginalPrice {
    final currentTotal =
        _currentProducts.values.fold(0.0, (sum, p) => sum + p.price);
    final newTotal =
        _newSelectedProducts.values.fold(0.0, (sum, p) => sum + p.price);
    return currentTotal + newTotal;
  }

  double get _savingsAmount {
    if (_bundlePrice == null) return 0.0;
    return _totalOriginalPrice - _bundlePrice!;
  }

  double get _savingsPercentage {
    if (_bundlePrice == null || _totalOriginalPrice == 0) return 0.0;
    return (_savingsAmount / _totalOriginalPrice * 100);
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) {
      Navigator.pop(context, true);
      return;
    }

    final l10n = AppLocalizations.of(context);

    // Validation
    final totalProducts = _currentProducts.length + _newSelectedProducts.length;
    if (totalProducts < 2) {
      _showErrorSnackBar(l10n.bundleMustHaveAtLeastTwoProducts);
      return;
    }

    if (totalProducts > 6) {
      _showErrorSnackBar(l10n.maximumProductsPerBundle);
      return;
    }

    if (_bundlePrice == null || _bundlePrice! <= 0) {
      _showErrorSnackBar(l10n.pleaseEnterValidPrices);
      return;
    }

    if (_bundlePrice! >= _totalOriginalPrice) {
      _showErrorSnackBar(l10n.bundlePriceMustBeLessThanTotal);
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_removedProductIds.isNotEmpty) {
        await Future.wait(
          _removedProductIds
              .map((id) => _cleanupProductBundleData(id, widget.bundle.id)),
        );
      }
      final batch = _firestore.batch();
      final bundleRef = _firestore.collection('bundles').doc(widget.bundle.id);

      // Combine all product IDs
      final allCurrentProductIds = {
        ..._currentProducts.keys,
        ..._newSelectedProducts.keys
      };
      final allProductIds = allCurrentProductIds.toList();

      // Calculate discount percentage
      final discountPercentage =
          ((_totalOriginalPrice - _bundlePrice!) / _totalOriginalPrice * 100);

      // Create updated bundle products list
      final updatedBundleProducts = <BundleProduct>[];

      // Add current products
      for (var product in _currentProducts.values) {
        updatedBundleProducts.add(BundleProduct(
          productId: product.id,
          productName: product.productName,
          originalPrice: product.price,
          imageUrl:
              product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
        ));
      }

      // Add new products
      for (var product in _newSelectedProducts.values) {
        updatedBundleProducts.add(BundleProduct(
          productId: product.id,
          productName: product.productName,
          originalPrice: product.price,
          imageUrl:
              product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
        ));
      }

      // Update bundle document
      batch.update(bundleRef, {
        'products': updatedBundleProducts.map((bp) => bp.toMap()).toList(),
        'totalBundlePrice': _bundlePrice,
        'totalOriginalPrice': _totalOriginalPrice,
        'discountPercentage': discountPercentage,
        'currency': _currentProducts.values.first.currency ?? 'TL',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update/remove bundleData for ALL products in bundle
      for (final productId in allProductIds) {
        final productRef =
            _firestore.collection('shop_products').doc(productId);
        final productDoc = await productRef.get();

        if (productDoc.exists) {
          final data = productDoc.data();
          final existingBundleData =
              data?['bundleData'] as List<dynamic>? ?? [];

          // Remove this bundle's old data
          final otherBundlesData = existingBundleData
              .where((bd) => bd['bundleId'] != widget.bundle.id)
              .toList();

          // Get other product IDs in this bundle
          final otherProductIds =
              allProductIds.where((id) => id != productId).toList();

          // Add updated bundle data for this bundle
          final newBundleData = {
            'bundleId': widget.bundle.id,
            'bundlePrice': _bundlePrice,
            'bundleDiscount': discountPercentage.round(),
            'bundleProductCount': allProductIds.length,
            'otherProductIds': otherProductIds,
          };

          otherBundlesData.add(newBundleData);

          // Update product with new bundleData
          batch.update(productRef, {
            'bundleIds': FieldValue.arrayUnion([widget.bundle.id]),
            'bundleData': otherBundlesData,
          });
        }
      }

      await batch.commit();

      _showSuccessSnackBar(l10n.bundleUpdatedSuccessfully);
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar(l10n.failedToUpdateBundle(e.toString()));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteBundle() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBundle,
            style: GoogleFonts.figtree(fontWeight: FontWeight.w700)),
        content:
            Text(l10n.deleteBundleConfirmation, style: GoogleFonts.figtree()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: GoogleFonts.figtree()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53E3E)),
            child: Text(l10n.delete,
                style: GoogleFonts.figtree(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      // Step 1: Clean up all products FIRST
      final allProductIds =
          widget.bundle.products.map((bp) => bp.productId).toList();

      final results = await Future.wait(
        allProductIds
            .map((id) => _cleanupProductBundleData(id, widget.bundle.id)),
      );

      final failedCount = results.where((success) => !success).length;
      if (failedCount > 0) {
        debugPrint('⚠️ $failedCount products failed cleanup');
      }

      // Step 2: Delete the bundle
      await _firestore.collection('bundles').doc(widget.bundle.id).delete();

      _showSuccessSnackBar(l10n.bundleDeletedSuccessfully);
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar(l10n.failedToDeleteBundle(e.toString()));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<bool> _cleanupProductBundleData(
      String productId, String bundleId) async {
    const maxRetries = 3;

    for (int i = 0; i < maxRetries; i++) {
      try {
        await _firestore.runTransaction((transaction) async {
          final productRef =
              _firestore.collection('shop_products').doc(productId);
          final doc = await transaction.get(productRef);

          if (!doc.exists) return; // Product deleted, nothing to clean

          final data = doc.data()!;
          final bundleData = List<Map<String, dynamic>>.from(
            (data['bundleData'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e)),
          );

          // Remove this bundle's data
          bundleData.removeWhere((bd) => bd['bundleId'] == bundleId);

          if (bundleData.isEmpty) {
            transaction.update(productRef, {
              'bundleIds': FieldValue.arrayRemove([bundleId]),
              'bundleData': FieldValue.delete(),
            });
          } else {
            transaction.update(productRef, {
              'bundleIds': FieldValue.arrayRemove([bundleId]),
              'bundleData': bundleData,
            });
          }
        });

        return true; // Success
      } catch (e) {
        debugPrint('Retry ${i + 1}/$maxRetries for product $productId: $e');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        }
      }
    }

    return false; // Failed after retries
  }

  void _showCriticalError(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final l10n = AppLocalizations.of(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(l10n.bundleInvalid),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context, true); // Exit screen
              },
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    });
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(l10n.editBundle, style: GoogleFonts.figtree()),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(l10n, isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildBundleSummary(isDark, l10n),
            if (_invalidProductIds.isNotEmpty) _buildCleanupBanner(l10n, isDark),
            _buildTabBar(l10n, isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCurrentProductsTab(l10n, isDark),
                  _buildAddProductsTab(l10n, isDark),
                ],
              ),
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
        l10n.editBundle,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A202C),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _isSaving ? null : _deleteBundle,
          icon: const Icon(Icons.delete_rounded),
          color: const Color(0xFFE53E3E),
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
    final totalProducts = _currentProducts.length + _newSelectedProducts.length;

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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                l10n.productsInBundle(totalProducts),
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
            '${_totalOriginalPrice.toStringAsFixed(2)} ${_currentProducts.values.first.currency ?? 'TL'}',
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
              prefixText: '${_currentProducts.values.first.currency ?? 'TL'} ',
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
                _currentProducts.values.first.currency ?? 'TL',
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

  Widget _buildCleanupBanner(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3182CE).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3182CE).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Color(0xFF3182CE),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.invalidProductsRemovedAutomatically(
                  _invalidProductIds.length),
              style: GoogleFonts.figtree(
                color: const Color(0xFF3182CE),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: [
          Tab(text: l10n.currentProductsCount(_currentProducts.length)),
          Tab(text: l10n.addProducts),
        ],
      ),
    );
  }

  Widget _buildCurrentProductsTab(AppLocalizations l10n, bool isDark) {
    if (_currentProducts.isEmpty) {
      return _buildEmptyState(
        l10n.noProducts,
        l10n.addProductsToThisBundle,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _currentProducts.length,
      itemBuilder: (context, index) {
        final product = _currentProducts.values.elementAt(index);
        return _buildCurrentProductCard(product, isDark, l10n);
      },
    );
  }

  Widget _buildCurrentProductCard(
      Product product, bool isDark, AppLocalizations l10n) {
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
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color:
                    isDark ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC),
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
                      color: isDark ? Colors.white : const Color(0xFF1A202C),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.price.toStringAsFixed(2)} ${product.currency ?? 'TL'}',
                    style: GoogleFonts.figtree(
                      color: const Color(0xFF667EEA),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _removeProduct(product.id),
              icon: const Icon(Icons.remove_circle_rounded),
              color: const Color(0xFFE53E3E),
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddProductsTab(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        _buildSearchBar(l10n, isDark),
        if (_newSelectedProducts.isNotEmpty)
          _buildNewSelectedCount(isDark, l10n),
        Expanded(
          child: _filteredProducts.isEmpty
              ? _buildEmptyState(
                  l10n.noProductsAvailable,
                  l10n.allProductsAlreadyInBundle,
                  isDark,
                )
              : _buildAvailableProductsList(isDark),
        ),
      ],
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        ),
      ),
    );
  }

  Widget _buildNewSelectedCount(bool isDark, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF667EEA).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF667EEA).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.add_circle_rounded,
            color: Color(0xFF667EEA),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.newProductsToAdd(_newSelectedProducts.length),
            style: GoogleFonts.figtree(
              color: const Color(0xFF667EEA),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableProductsList(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final isSelected = _newSelectedProducts.containsKey(product.id);
        return _buildAvailableProductCard(product, isSelected, isDark);
      },
    );
  }

  Widget _buildAvailableProductCard(
      Product product, bool isSelected, bool isDark) {
    final hasSalePreference = product.discountThreshold != null &&
        product.bulkDiscountPercentage != null &&
        product.discountThreshold! > 0 &&
        product.bulkDiscountPercentage! > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF667EEA)
              : isDark
                  ? const Color(0xFF4A5568)
                  : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: hasSalePreference
                  ? null
                  : () => _toggleNewProductSelection(product),
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: hasSalePreference ? 0.6 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF667EEA)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF667EEA)
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
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: isDark
                              ? const Color(0xFF4A5568)
                              : const Color(0xFFF7FAFC),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
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
                                  size: 18,
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
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A202C),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${product.price.toStringAsFixed(2)} ${product.currency ?? 'TL'}',
                              style: GoogleFonts.figtree(
                                color: const Color(0xFF667EEA),
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
                      AppLocalizations.of(context)
                              .removeSalePreferenceToCreateBundle ??
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
                        AppLocalizations.of(context).remove ?? 'Remove',
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
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n, bool isDark) {
    if (!_hasChanges) return const SizedBox.shrink();

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
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38A169),
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
                    l10n.saveChanges,
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

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
