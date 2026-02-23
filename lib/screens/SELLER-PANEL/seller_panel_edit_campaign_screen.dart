import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/product.dart';
import '../../providers/seller_panel_provider.dart';
import '../../generated/l10n/app_localizations.dart';
import 'seller_panel_campaign_discount_screen.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SellerPanelEditCampaignScreen extends StatefulWidget {
  final Map<String, dynamic> campaign;
  final String shopId;

  const SellerPanelEditCampaignScreen({
    super.key,
    required this.campaign,
    required this.shopId,
  });

  @override
  State<SellerPanelEditCampaignScreen> createState() =>
      _SellerPanelEditCampaignScreenState();
}

class _SellerPanelEditCampaignScreenState
    extends State<SellerPanelEditCampaignScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Product> _campaignedProducts = [];
  List<Product> _availableProducts = [];
  List<Product> _selectedNewProducts = [];

  final Map<String, TextEditingController> _discountControllers = {};
  final Map<String, double> _productDiscounts = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Set<String> _removingProducts = {}; // Track products being removed

  /// Real-time listener for campaigned products (kept — justified for
  /// multi-member collaboration, but now with .limit())
  StreamSubscription<QuerySnapshot>? _campaignedProductsSubscription;

  // ✅ CHANGE: Replaced full-collection available products listener with:
  //   1. One-time paginated fetch (_loadAvailableProducts)
  //   2. Targeted per-document listeners ONLY for blocked products
  DocumentSnapshot? _lastAvailableDoc;
  bool _hasMoreAvailable = true;
  bool _isLoadingMoreAvailable = false;
  final ScrollController _availableScrollController = ScrollController();
  final Map<String, StreamSubscription<DocumentSnapshot>>
      _blockedProductListeners = {};

  // ✅ CHANGE: Added pagination for campaigned products tab
  DocumentSnapshot? _lastCampaignedDoc;
  bool _hasMoreCampaigned = true;
  bool _isLoadingMoreCampaigned = false;
  final ScrollController _campaignedScrollController = ScrollController();

  TabController? _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLoadingAvailable = false;
  String? _errorMessage;

  // Snackbar management
  Timer? _snackbarTimer;
  int _pendingRemovalCount = 0;

  static const double _minDiscountPercentage = 5.0;
  static const double _maxDiscountPercentage = 90.0;
  static const int _pageSize = 20;

  // Viewer role state
  bool _isViewer = false;
  bool _isCheckingRole = true;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadCampaignedProducts();

    // ✅ CHANGE: Scroll listeners for pagination
    _campaignedScrollController.addListener(_onCampaignedScroll);
    _availableScrollController.addListener(_onAvailableScroll);
  }

  // ── Scroll-based pagination triggers ─────────────────────────────────
  void _onCampaignedScroll() {
    if (_campaignedScrollController.position.pixels >=
            _campaignedScrollController.position.maxScrollExtent - 200 &&
        _hasMoreCampaigned &&
        !_isLoadingMoreCampaigned) {
      _loadMoreCampaignedProducts();
    }
  }

  void _onAvailableScroll() {
    if (_availableScrollController.position.pixels >=
            _availableScrollController.position.maxScrollExtent - 200 &&
        _hasMoreAvailable &&
        !_isLoadingMoreAvailable) {
      _loadMoreAvailableProducts();
    }
  }

  /// Checks if the current user has only viewer role for the shop.
  Future<void> _checkUserRole() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        _initTabController();
        return;
      }

      final shopDoc =
          await _firestore.collection('shops').doc(widget.shopId).get();

      if (shopDoc.exists && mounted) {
        final shopData = shopDoc.data();
        if (shopData != null) {
          final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
          _isViewer = viewers.contains(currentUserId);
        }
      }
    } catch (e) {
      debugPrint('Error checking user role: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingRole = false);
        _initTabController();
      }
    }
  }

  void _initTabController() {
    _tabController = TabController(
      length: _isViewer ? 1 : 2,
      vsync: this,
    );

    if (!_isViewer) {
      _tabController!.addListener(() {
        // ✅ CHANGE: Load available products only once on first tab switch
        if (_tabController!.index == 1 && _availableProducts.isEmpty) {
          _loadAvailableProducts();
        }
      });
    }
  }

  @override
  void dispose() {
    _campaignedProductsSubscription?.cancel();
    _cancelBlockedListeners();
    _tabController?.dispose();
    _snackbarTimer?.cancel();
    _campaignedScrollController.dispose();
    _availableScrollController.dispose();
    for (final controller in _discountControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BLOCKED PRODUCT LISTENERS — targeted, per-document, self-cancelling
  // ═══════════════════════════════════════════════════════════════════════

  /// Returns true if product cannot receive a campaign discount.
  bool _isProductBlocked(Product product) {
    final hasSalePreference = product.discountThreshold != null &&
        product.bulkDiscountPercentage != null &&
        product.discountThreshold! > 0 &&
        product.bulkDiscountPercentage! > 0;
    final isInBundle = product.bundleIds.isNotEmpty;
    return hasSalePreference || isInBundle;
  }

  /// Attaches individual document listeners ONLY for blocked products.
  /// When a blocked product becomes unblocked (e.g. sale preference removed),
  /// the listener self-cancels. Cost: 1 read per change per blocked product.
  void _attachBlockedProductListeners(List<Product> products) {
    for (final product in products) {
      if (!_isProductBlocked(product)) continue;
      if (_blockedProductListeners.containsKey(product.id)) continue;

      _blockedProductListeners[product.id] = _firestore
          .collection('shop_products')
          .doc(product.id)
          .snapshots()
          .listen(
        (docSnapshot) {
          if (!mounted || !docSnapshot.exists) return;

          final updatedProduct = Product.fromDocument(docSnapshot);
          final stillBlocked = _isProductBlocked(updatedProduct);

          setState(() {
            // Update in available products list
            final availIdx =
                _availableProducts.indexWhere((p) => p.id == product.id);
            if (availIdx != -1) {
              _availableProducts[availIdx] = updatedProduct;
            }
          });

          // Self-cancel when no longer blocked
          if (!stillBlocked) {
            _blockedProductListeners[product.id]?.cancel();
            _blockedProductListeners.remove(product.id);
          }
        },
        onError: (e) {
          debugPrint('Error listening to blocked product ${product.id}: $e');
          _blockedProductListeners[product.id]?.cancel();
          _blockedProductListeners.remove(product.id);
        },
      );
    }
  }

  void _cancelBlockedListeners() {
    for (final sub in _blockedProductListeners.values) {
      sub.cancel();
    }
    _blockedProductListeners.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CAMPAIGNED PRODUCTS — real-time listener with limit (justified for
  // multi-member collaboration)
  // ═══════════════════════════════════════════════════════════════════════

  /// Loads campaigned products with a real-time listener.
  /// Listener is justified here because multiple team members may be
  /// editing the same campaign simultaneously.
  Future<void> _loadCampaignedProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final campaignId = widget.campaign['id'] as String;

    _campaignedProductsSubscription?.cancel();
    _campaignedProductsSubscription = _firestore
        .collection('shop_products')
        .where('shopId', isEqualTo: widget.shopId)
        .where('campaign', isEqualTo: campaignId)
        .orderBy('createdAt', descending: true)
        // ✅ CHANGE: Added limit to prevent unbounded reads
        .limit(50)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;

        final products =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        // Initialize controllers for new products only
        for (final product in products) {
          if (!_discountControllers.containsKey(product.id)) {
            _discountControllers[product.id] = TextEditingController(
              text: (product.discountPercentage ?? 0).toStringAsFixed(1),
            );
            _focusNodes[product.id] = FocusNode();
          }
          _productDiscounts[product.id] =
              (product.discountPercentage ?? 0.0).toDouble();
        }

        // Clean up controllers for removed products
        final currentIds = products.map((p) => p.id).toSet();
        final controllersToRemove = _discountControllers.keys
            .where((id) => !currentIds.contains(id))
            .toList();
        for (final id in controllersToRemove) {
          _discountControllers[id]?.dispose();
          _discountControllers.remove(id);
          _focusNodes[id]?.dispose();
          _focusNodes.remove(id);
          _productDiscounts.remove(id);
        }

        // ✅ CHANGE: Track pagination state from listener results
        _lastCampaignedDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreCampaigned = snapshot.docs.length == 50;

        setState(() {
          _campaignedProducts = products;
          _isLoading = false;
        });
      },
      onError: (error) {
        debugPrint('Error listening to campaigned products: $error');
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load campaigned products: $error';
            _isLoading = false;
          });
        }
      },
    );
  }

  /// Loads more campaigned products beyond the listener's limit.
  Future<void> _loadMoreCampaignedProducts() async {
    if (!_hasMoreCampaigned || _isLoadingMoreCampaigned) return;
    if (_lastCampaignedDoc == null) return;

    setState(() => _isLoadingMoreCampaigned = true);

    try {
      final campaignId = widget.campaign['id'] as String;
      final snapshot = await _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: widget.shopId)
          .where('campaign', isEqualTo: campaignId)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastCampaignedDoc!)
          .limit(_pageSize)
          .get();

      final newProducts =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

      for (final product in newProducts) {
        if (!_discountControllers.containsKey(product.id)) {
          _discountControllers[product.id] = TextEditingController(
            text: (product.discountPercentage ?? 0).toStringAsFixed(1),
          );
          _focusNodes[product.id] = FocusNode();
        }
        _productDiscounts[product.id] =
            (product.discountPercentage ?? 0.0).toDouble();
      }

      setState(() {
        _campaignedProducts.addAll(newProducts);
        _lastCampaignedDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreCampaigned = snapshot.docs.length == _pageSize;
        _isLoadingMoreCampaigned = false;
      });
    } catch (e) {
      debugPrint('Error loading more campaigned products: $e');
      setState(() => _isLoadingMoreCampaigned = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AVAILABLE PRODUCTS — paginated one-time fetch + targeted blocked
  // listeners. No full-collection listener.
  // ═══════════════════════════════════════════════════════════════════════

  /// ✅ CHANGE: Replaced full-collection real-time listener with paginated
  /// one-time fetch. Reads only 20 docs per page instead of the entire shop.
  /// Targeted per-document listeners are attached only for blocked products.
  Future<void> _loadAvailableProducts({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoadingAvailable = true;
        _lastAvailableDoc = null;
        _hasMoreAvailable = true;
        _errorMessage = null;
      });
      _cancelBlockedListeners();
    } else {
      if (!_hasMoreAvailable || _isLoadingMoreAvailable) return;
      setState(() => _isLoadingMoreAvailable = true);
    }

    try {
      // ✅ CHANGE: Requires campaign field standardization.
      // Products not in any campaign must have campaign == ''
      // instead of the field being deleted. See migration note below.
      Query query = _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: widget.shopId)
          .where('campaign', isEqualTo: '')
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (loadMore && _lastAvailableDoc != null) {
        query = query.startAfterDocument(_lastAvailableDoc!);
      }

      final snapshot = await query.get();
      final products =
          snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

      setState(() {
        if (loadMore) {
          _availableProducts.addAll(products);
        } else {
          _availableProducts = products;
        }
        _lastAvailableDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreAvailable = snapshot.docs.length == _pageSize;
        _isLoadingAvailable = false;
        _isLoadingMoreAvailable = false;
      });

      // Attach listeners ONLY for blocked products in this page
      _attachBlockedProductListeners(products);
    } catch (e) {
      debugPrint('Error loading available products: $e');
      setState(() {
        _isLoadingAvailable = false;
        _isLoadingMoreAvailable = false;
        _errorMessage = 'Error loading available products: $e';
      });
    }
  }

  /// Convenience method for scroll-triggered pagination.
  Future<void> _loadMoreAvailableProducts() async {
    await _loadAvailableProducts(loadMore: true);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CAMPAIGN OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════

  // ✅ CHANGE: Removed redundant Firestore read — product data is already
  // available in memory from the listener. Saves 1 read per removal.
  Future<void> _removeFromCampaign(Product product) async {
    setState(() {
      _removingProducts.add(product.id);
    });

    try {
      final updateData = <String, dynamic>{
        // ✅ CHANGE: Set to '' instead of FieldValue.delete() for queryability
        'campaign': '',
        'campaignName': '',
        'discountPercentage': FieldValue.delete(),
        'originalPrice': FieldValue.delete(),
      };

      // ✅ CHANGE: Use in-memory product data — no extra read needed
      if (product.originalPrice != null) {
        updateData['price'] = product.originalPrice;
      }

      await _firestore
          .collection('shop_products')
          .doc(product.id)
          .update(updateData);

      setState(() {
        _campaignedProducts.removeWhere((p) => p.id == product.id);
        _discountControllers[product.id]?.dispose();
        _discountControllers.remove(product.id);
        _focusNodes[product.id]?.dispose();
        _focusNodes.remove(product.id);
        _productDiscounts.remove(product.id);
        _removingProducts.remove(product.id);

        // Add back to available list immediately for UX
        final updatedProduct = product.copyWith(
          setDiscountPercentageNull: true,
          setOriginalPriceNull: true,
        );
        if (!_availableProducts.any((p) => p.id == product.id)) {
          _availableProducts.insert(0, updatedProduct);
        }
      });

      // Batched snackbar display
      _pendingRemovalCount++;
      _snackbarTimer?.cancel();
      _snackbarTimer = Timer(const Duration(milliseconds: 500), () {
        if (_pendingRemovalCount > 0) {
          final message = _pendingRemovalCount == 1
              ? context.l10n.productRemovedFromCampaign
              : '${_pendingRemovalCount} ${context.l10n.productsRemovedFromCampaign ?? 'products removed from campaign'}';
          _showSuccessSnackBar(message);
          _pendingRemovalCount = 0;
        }
      });

      Provider.of<SellerPanelProvider>(context, listen: false)
          .refreshCampaignStatus();
    } catch (e) {
      setState(() {
        _removingProducts.remove(product.id);
      });
      _showErrorSnackBar('${context.l10n.failedToRemoveProduct}: $e');
    }
  }

  Future<void> _updateDiscount(Product product, double newDiscount) async {
    // Snapshot for rollback
    final prevDiscount = _productDiscounts[product.id] ?? 0.0;

    // Optimistic update
    setState(() => _productDiscounts[product.id] = newDiscount);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('updateCampaignProductDiscount');

      await callable.call({
        'productId': product.id,
        'campaignId': widget.campaign['id'],
        'shopId': widget.shopId,
        'newDiscount': newDiscount,
      });

      _showSuccessSnackBar(
          context.l10n.discountUpdatedSuccessfully ?? 'Discount updated');
    } catch (e) {
      // Rollback
      setState(() => _productDiscounts[product.id] = prevDiscount);
      _showErrorSnackBar('${context.l10n.failedToUpdateDiscount}: $e');
    }
  }

  Future<void> _addProductsToCampaign() async {
    if (_selectedNewProducts.isEmpty) {
      _showErrorSnackBar(context.l10n.pleaseSelectProductsToAdd);
      return;
    }

    // Deduplicate selected products by ID
    final seenIds = <String>{};
    final uniqueProducts = _selectedNewProducts.where((product) {
      if (seenIds.contains(product.id)) {
        return false;
      }
      seenIds.add(product.id);
      return true;
    }).toList();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SellerPanelCampaignDiscountScreen(
          campaign: widget.campaign,
          selectedProducts: uniqueProducts,
          shopId: widget.shopId,
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
    ).then((_) {
      // Refresh data when returning from discount screen
      _loadCampaignedProducts();
      // ✅ CHANGE: Refresh available products (one-time fetch, not listener)
      _loadAvailableProducts();
      setState(() {
        _selectedNewProducts.clear();
        _tabController?.animateTo(0);
      });
    });
  }

  void _toggleProductSelection(Product product) {
    setState(() {
      final existingIndex =
          _selectedNewProducts.indexWhere((p) => p.id == product.id);
      if (existingIndex != -1) {
        _selectedNewProducts.removeAt(existingIndex);
      } else {
        _selectedNewProducts.add(product);
      }
    });
  }

  bool _validateDiscountPercentage(String value) {
    if (value.isEmpty) return true;
    final discount = double.tryParse(value);
    if (discount == null) return false;
    return discount >= _minDiscountPercentage &&
        discount <= _maxDiscountPercentage;
  }

  Future<void> _removeFromCampaignKeepDiscount(Product product) async {
    setState(() => _removingProducts.add(product.id));

    // Snapshot for rollback
    final prevCampaigned = List<Product>.from(_campaignedProducts);
    final prevAvailable = List<Product>.from(_availableProducts);
    final prevDiscount = _productDiscounts[product.id];
    final prevControllerText = _discountControllers[product.id]?.text ?? '';

    // Optimistic update
    setState(() {
      _campaignedProducts.removeWhere((p) => p.id == product.id);
      if (!_availableProducts.any((p) => p.id == product.id)) {
        _availableProducts.insert(0, product);
      }
      _discountControllers[product.id]?.dispose();
      _discountControllers.remove(product.id);
      _focusNodes[product.id]?.dispose();
      _focusNodes.remove(product.id);
      _productDiscounts.remove(product.id);
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('removeProductFromCampaign');

      await callable.call({
        'productId': product.id,
        'campaignId': widget.campaign['id'],
        'shopId': widget.shopId,
        'keepDiscount': true,
      });

      _showSuccessSnackBar(context.l10n.productRemovedDiscountKept);
      Provider.of<SellerPanelProvider>(context, listen: false)
          .refreshCampaignStatus();
    } catch (e) {
      // Rollback lists AND recreate controller/focusNode
      setState(() {
        _campaignedProducts = prevCampaigned;
        _availableProducts = prevAvailable;
        _productDiscounts[product.id] = prevDiscount ?? 0.0;
        _discountControllers[product.id] =
            TextEditingController(text: prevControllerText);
        _focusNodes[product.id] = FocusNode();
        _removingProducts.remove(product.id);
      });
      _showErrorSnackBar('${context.l10n.failedToRemoveProduct}: $e');
      return;
    }

    setState(() => _removingProducts.remove(product.id));
  }

  Future<void> _removeFromCampaignAndDiscount(Product product) async {
    setState(() => _removingProducts.add(product.id));

    // Snapshot for rollback
    final prevCampaigned = List<Product>.from(_campaignedProducts);
    final prevAvailable = List<Product>.from(_availableProducts);
    final prevDiscount = _productDiscounts[product.id];
    final prevControllerText = _discountControllers[product.id]?.text ?? '';

    // Optimistic update
    final restoredProduct = product.copyWith(
      setDiscountPercentageNull: true,
      setOriginalPriceNull: true,
    );

    setState(() {
      _campaignedProducts.removeWhere((p) => p.id == product.id);
      if (!_availableProducts.any((p) => p.id == product.id)) {
        _availableProducts.insert(0, restoredProduct);
      }
      _discountControllers[product.id]?.dispose();
      _discountControllers.remove(product.id);
      _focusNodes[product.id]?.dispose();
      _focusNodes.remove(product.id);
      _productDiscounts.remove(product.id);
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('removeProductFromCampaign');

      await callable.call({
        'productId': product.id,
        'campaignId': widget.campaign['id'],
        'shopId': widget.shopId,
        'keepDiscount': false,
      });

      _showSuccessSnackBar(context.l10n.productRemovedDiscountRestored);
      Provider.of<SellerPanelProvider>(context, listen: false)
          .refreshCampaignStatus();
    } catch (e) {
      // Rollback lists AND recreate controller/focusNode
      setState(() {
        _campaignedProducts = prevCampaigned;
        _availableProducts = prevAvailable;
        _productDiscounts[product.id] = prevDiscount ?? 0.0;
        _discountControllers[product.id] =
            TextEditingController(text: prevControllerText);
        _focusNodes[product.id] = FocusNode();
        _removingProducts.remove(product.id);
      });
      _showErrorSnackBar('${context.l10n.failedToRemoveProduct}: $e');
      return;
    }

    setState(() => _removingProducts.remove(product.id));
  }

  void _showRemoveDialog(Product product, AppLocalizations l10n) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(
          l10n.removeFromCampaign,
          style: GoogleFonts.figtree(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        message: Text(
          '${l10n.chooseRemovalOption}',
          style: GoogleFonts.figtree(
            fontSize: 14,
            color: CupertinoColors.secondaryLabel,
          ),
        ),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _removeFromCampaignKeepDiscount(product);
            },
            child: Column(
              children: [
                Text(
                  l10n.keepDiscountRemoveFromCampaign,
                  style: GoogleFonts.figtree(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF10B981),
                  ),
                ),
                Text(
                  l10n.keepDiscountDescription,
                  style: GoogleFonts.figtree(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _removeFromCampaignAndDiscount(product);
            },
            child: Column(
              children: [
                Text(
                  l10n.removeDiscountAndFromCampaign,
                  style: GoogleFonts.figtree(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                Text(
                  l10n.removeDiscountDescription,
                  style: GoogleFonts.figtree(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(
            l10n.cancel,
            style: GoogleFonts.figtree(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
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
        margin: const EdgeInsets.all(12),
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
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading || _isCheckingRole || _tabController == null) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(l10n.editCampaign),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
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
            _buildCampaignHeader(l10n, isDark),
            _buildTabBar(l10n, isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _isViewer
                    ? [_buildCampaignedProductsTab(l10n, isDark)]
                    : [
                        _buildCampaignedProductsTab(l10n, isDark),
                        _buildAddProductsTab(l10n, isDark),
                      ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isViewer ? null : _buildFloatingActionButton(l10n),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n, bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
      foregroundColor: isDark ? Colors.white : const Color(0xFF1A202C),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      title: Text(
        l10n.editCampaign,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A202C),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
        ),
      ),
    );
  }

  Widget _buildCampaignHeader(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1B23), const Color(0xFF2D3748)]
              : [Colors.white, const Color(0xFFF7FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : const Color(0xFF64748B).withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35).withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.campaign['name'] ?? l10n.campaign,
                      style: GoogleFonts.figtree(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A202C),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4299E1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4299E1).withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        '${_campaignedProducts.length} ${l10n.productsInCampaign}',
                        style: GoogleFonts.figtree(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF4299E1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.campaign['description']?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2D3748).withOpacity(0.3)
                    : const Color(0xFFF7FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF4A5568)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Text(
                widget.campaign['description'],
                style: GoogleFonts.figtree(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFFA0AAB8)
                      : const Color(0xFF4A5568),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(AppLocalizations l10n, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00A86B), Color(0xFF00C574)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00A86B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Theme.of(context).brightness == Brightness.light
            ? Colors.grey[600]
            : Colors.grey[400],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        onTap: (index) {
          if (index == 1 && !_isViewer && _availableProducts.isEmpty) {
            _loadAvailableProducts();
          }
        },
        tabs: _isViewer
            ? [
                Tab(
                  height: 40,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        '${l10n.campaignProducts} (${_campaignedProducts.length})'),
                  ),
                ),
              ]
            : [
                Tab(
                  height: 40,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        '${l10n.campaignProducts} (${_campaignedProducts.length})'),
                  ),
                ),
                Tab(
                  height: 40,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(child: Text(l10n.addProducts)),
                  ),
                ),
              ],
      ),
    );
  }

  Widget _buildCampaignedProductsTab(AppLocalizations l10n, bool isDark) {
    if (_campaignedProducts.isEmpty) {
      return _buildEmptyState(
        l10n.noProductsInCampaign,
        l10n.addProductsToCampaignToGetStarted,
        Icons.campaign_outlined,
        isDark,
      );
    }

    return ListView.builder(
      controller: _campaignedScrollController, // ✅ CHANGE: pagination
      padding: const EdgeInsets.all(12),
      itemCount:
          _campaignedProducts.length + (_isLoadingMoreCampaigned ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _campaignedProducts.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final product = _campaignedProducts[index];
        return _buildCampaignedProductCard(product, l10n, isDark);
      },
    );
  }

  Widget _buildAddProductsTab(AppLocalizations l10n, bool isDark) {
    if (_isLoadingAvailable && _availableProducts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_availableProducts.isEmpty && !_isLoadingAvailable) {
      return _buildEmptyState(
        l10n.noAvailableProducts,
        l10n.allProductsAlreadyInCampaigns,
        Icons.inventory_2_outlined,
        isDark,
      );
    }

    return Column(
      children: [
        if (_selectedNewProducts.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4299E1).withOpacity(0.1),
                  const Color(0xFF3182CE).withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF4299E1).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: const Color(0xFF4299E1),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedNewProducts.length} ${l10n.productsSelected(_selectedNewProducts.length)}',
                  style: GoogleFonts.figtree(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4299E1),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _availableScrollController, // ✅ CHANGE: pagination
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount:
                _availableProducts.length + (_isLoadingMoreAvailable ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _availableProducts.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final product = _availableProducts[index];
              final isSelected =
                  _selectedNewProducts.any((p) => p.id == product.id);
              return _buildAvailableProductCard(product, isDark, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCampaignedProductCard(
      Product product, AppLocalizations l10n, bool isDark) {
    final controller = _discountControllers[product.id]!;
    final focusNode = _focusNodes[product.id]!;
    final discount = _productDiscounts[product.id] ?? 0.0;
    final hasDiscount = discount > 0;
    final isRemoving = _removingProducts.contains(product.id);

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
          color: hasDiscount
              ? const Color(0xFF38A169).withOpacity(0.3)
              : isDark
                  ? const Color(0xFF4A5568)
                  : const Color(0xFFE2E8F0),
          width: hasDiscount ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasDiscount
                ? const Color(0xFF38A169).withOpacity(0.1)
                : isDark
                    ? Colors.black.withOpacity(0.15)
                    : const Color(0xFF64748B).withOpacity(0.06),
            blurRadius: hasDiscount ? 10 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isDark
                        ? const Color(0xFF2D3748)
                        : const Color(0xFFF7FAFC),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF4A5568)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: product.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrls.first,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: isDark
                                  ? const Color(0xFF2D3748)
                                  : const Color(0xFFF7FAFC),
                              child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark
                                  ? const Color(0xFF2D3748)
                                  : const Color(0xFFF7FAFC),
                              child: Icon(
                                Icons.image_not_supported_rounded,
                                color: isDark
                                    ? const Color(0xFF718096)
                                    : const Color(0xFF94A3B8),
                                size: 24,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.image_rounded,
                            color: isDark
                                ? const Color(0xFF718096)
                                : const Color(0xFF94A3B8),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: GoogleFonts.figtree(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A202C),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${product.price.toStringAsFixed(2)} ${product.currency ?? '\$'}',
                            style: GoogleFonts.figtree(
                              color: hasDiscount
                                  ? const Color(0xFF38A169)
                                  : const Color(0xFF667EEA),
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF38A169),
                                    Color(0xFF2F855A)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF38A169)
                                        .withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                '-${discount.toStringAsFixed(1)}%',
                                style: GoogleFonts.figtree(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Remove Button — hidden for viewers
                if (!_isViewer)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isRemoving
                          ? Colors.grey.withOpacity(0.3)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: isRemoving
                        ? const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFE53E3E)),
                              ),
                            ),
                          )
                        : IconButton(
                            onPressed: () => _showRemoveDialog(product, l10n),
                            icon: const Icon(
                              Icons.remove_circle_rounded,
                              color: Color(0xFFE53E3E),
                              size: 24,
                            ),
                            tooltip: l10n.removeFromCampaign,
                            splashRadius: 20,
                          ),
                  ),
              ],
            ),

            // Discount controls — hidden for viewers
            if (!_isViewer) ...[
              const SizedBox(height: 12),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      isDark
                          ? const Color(0xFF4A5568)
                          : const Color(0xFFE2E8F0),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Discount Input
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      onChanged: (value) {
                        final discount = double.tryParse(value) ?? 0.0;
                        setState(() {
                          _productDiscounts[product.id] = discount;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: l10n.discountPercentage,
                        hintText: '0',
                        suffixText: '%',
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2D3748)
                            : const Color(0xFFF7FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF4A5568)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? const Color(0xFF4A5568)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF667EEA),
                            width: 1.5,
                          ),
                        ),
                        labelStyle: GoogleFonts.figtree(
                          color: isDark
                              ? const Color(0xFFA0AAB8)
                              : const Color(0xFF64748B),
                          fontSize: 13,
                        ),
                        helperText:
                            '${l10n.min}: $_minDiscountPercentage%, ${l10n.max}: $_maxDiscountPercentage%',
                        helperStyle: GoogleFonts.figtree(
                          color: isDark
                              ? const Color(0xFF718096)
                              : const Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      style: GoogleFonts.figtree(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1A202C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        final discountText = controller.text.trim();
                        if (discountText.isEmpty) {
                          _updateDiscount(product, 0.0);
                        } else {
                          final discount = double.tryParse(discountText);
                          if (discount != null &&
                              _validateDiscountPercentage(discountText)) {
                            _updateDiscount(product, discount);
                          } else {
                            _showErrorSnackBar(l10n.invalidDiscountPercentage);
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        l10n.update,
                        style: GoogleFonts.figtree(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableProductCard(
      Product product, bool isDark, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              ? const Color(0xFF667EEA)
              : isDark
                  ? const Color(0xFF4A5568)
                  : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFF667EEA).withOpacity(0.1)
                : isDark
                    ? Colors.black.withOpacity(0.15)
                    : const Color(0xFF64748B).withOpacity(0.06),
            blurRadius: isSelected ? 8 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC),
            border: Border.all(
              color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE2E8F0),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.imageUrls.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: product.imageUrls.first,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: isDark
                          ? const Color(0xFF2D3748)
                          : const Color(0xFFF7FAFC),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: isDark
                          ? const Color(0xFF2D3748)
                          : const Color(0xFFF7FAFC),
                      child: Icon(
                        Icons.image_not_supported_rounded,
                        color: isDark
                            ? const Color(0xFF718096)
                            : const Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ),
                  )
                : Icon(
                    Icons.image_rounded,
                    color: isDark
                        ? const Color(0xFF718096)
                        : const Color(0xFF94A3B8),
                    size: 20,
                  ),
          ),
        ),
        title: Text(
          product.productName,
          style: GoogleFonts.figtree(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isDark ? Colors.white : const Color(0xFF1A202C),
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${product.price.toStringAsFixed(2)} ${product.currency ?? '\$'}',
            style: GoogleFonts.figtree(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: const Color(0xFF667EEA),
            ),
          ),
        ),
        trailing: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF667EEA) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : isDark
                      ? const Color(0xFF4A5568)
                      : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
          ),
          child: Checkbox(
            value: isSelected,
            onChanged: (value) => _toggleProductSelection(product),
            activeColor: Colors.transparent,
            checkColor: Colors.white,
            side: BorderSide.none,
          ),
        ),
        onTap: () => _toggleProductSelection(product),
      ),
    );
  }

  Widget _buildEmptyState(
      String title, String subtitle, IconData icon, bool isDark) {
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
                border: Border.all(
                  color: const Color(0xFF667EEA).withOpacity(0.2),
                ),
              ),
              child: Icon(
                icon,
                size: 48,
                color: const Color(0xFF667EEA),
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
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton(AppLocalizations l10n) {
    if (_tabController?.index != 1 || _selectedNewProducts.isEmpty) {
      return null;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _addProductsToCampaign,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.add_rounded, size: 20),
        label: Text(
          _isSaving
              ? l10n.adding
              : '${l10n.add} ${_selectedNewProducts.length} ${l10n.products}',
          style: GoogleFonts.figtree(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
