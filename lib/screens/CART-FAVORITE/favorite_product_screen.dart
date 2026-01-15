// lib/screens/CART-FAVORITE/favorite_product_screen.dart - REFACTORED v2.0 (Simplified + Production Grade)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/favorite_product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/product_card_4.dart';
import '../../widgets/product_card_4_shimmer.dart';
import '../../widgets/favorite_basket_widget.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/favorites_sharing_service.dart';
import '../market_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/product_option_selector.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // State variables
  bool _isAddingToCart = false;
  bool _isInitialLoading = true;
  static const int _pageSize = 20;
  String? _selectedProductId;
  // Controllers and subscriptions
  StreamSubscription<User?>? _authSubscription;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _bottomSheetController;
  late Animation<Offset> _bottomSheetAnimation;
  // Search
  String _searchQuery = '';
  Timer? _searchDebouncer;

  // Loading timeout
  Timer? _loadingTimeoutTimer;
  static const Duration _maxLoadingDuration = Duration(seconds: 5);

  // Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Lifecycle observer
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _setupAnimations();
    _setupScrollListener();
    _setupAuthListener();    
    _checkCacheAndInitialize();
    _startLoadingTimeout();
  }

  // ========================================================================
  // SETUP METHODS
  // ========================================================================

  void _setupScrollListener() {
  _scrollController.addListener(() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadNextPage();
    }
  });
}

void _setupAnimations() {
  _bottomSheetController = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: this,
  );
  _bottomSheetAnimation = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _bottomSheetController,
    curve: Curves.easeInOut,
  ));
}

 void _setupAuthListener() {
  _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user == null && mounted) {
      setState(() => _selectedProductId = null); // ✅ FIXED
    }
  });
}

  // ========================================================================
  // LIFECYCLE MANAGEMENT (Smart Listeners)
  // ========================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App in background - disable real-time updates
      favoriteProvider.disableLiveUpdates();
      debugPrint('🔴 App paused - favorites listener disabled');
    } else if (state == AppLifecycleState.resumed) {
      // App resumed - enable real-time updates
      favoriteProvider.enableLiveUpdates();
      debugPrint('🟢 App resumed - favorites listener enabled');
    }
  }

  // ========================================================================
  // INITIALIZATION
  // ========================================================================

  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(_maxLoadingDuration, () {
      if (mounted && _isInitialLoading) {
        debugPrint('⚠️ Loading timeout reached - forcing shimmer off');
        if (mounted) {
          setState(() => _isInitialLoading = false);
        }
      }
    });
  }

  void _checkCacheAndInitialize() {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);
    final currentBasketId = favoriteProvider.selectedBasketId;

    final hasCachedData = favoriteProvider.paginatedFavorites.isNotEmpty;
    final shouldReload =
        favoriteProvider.shouldReloadFavorites(currentBasketId);

    if (hasCachedData && !shouldReload) {
      setState(() => _isInitialLoading = false);
      _loadingTimeoutTimer?.cancel();
      debugPrint(
          '✅ Using cached data - ${favoriteProvider.paginatedFavorites.length} items');
    } else {
      // ✅ FIX: If cached data is empty and no more data, hide shimmer immediately
      if (!hasCachedData && !favoriteProvider.hasMoreData && favoriteProvider.isInitialLoadComplete) {
        setState(() => _isInitialLoading = false);
        _loadingTimeoutTimer?.cancel();
        debugPrint('✅ No cached data and no more to load - shimmer hidden');
      } else {
        debugPrint('🔄 Loading fresh data');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadDataIfNeeded();
        });
      }
    }
  }

  Future<void> _loadDataIfNeeded() async {
    if (!mounted) return;

    try {
      final favoriteProvider =
          Provider.of<FavoriteProvider>(context, listen: false);
      final currentBasketId = favoriteProvider.selectedBasketId;

      final hasCachedData = favoriteProvider.paginatedFavorites.isNotEmpty;
      final shouldReload =
          favoriteProvider.shouldReloadFavorites(currentBasketId);

      if (hasCachedData && !shouldReload) {
        debugPrint('✅ Using cached data - no reload needed');
        if (mounted) setState(() => _isInitialLoading = false);
        _loadingTimeoutTimer?.cancel();
        return;
      }

      if (shouldReload) {
        debugPrint('🔄 Loading favorites - basket changed or first load');
        await _resetPaginationAndLoad();
        if (mounted) setState(() => _isInitialLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error in _loadDataIfNeeded: $e');
      if (mounted) setState(() => _isInitialLoading = false);
    } finally {
      _loadingTimeoutTimer?.cancel();
    }
  }

Future<void> _resetPaginationAndLoad() async {
  try {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);

    setState(() {
      // ✅ REMOVED: _selectedProducts.clear() (no longer needed)
      _isInitialLoading = true;
    });

    _startLoadingTimeout();
    favoriteProvider.resetPagination();
    await _loadNextPage();
  } catch (e) {
    debugPrint('❌ Error in _resetPaginationAndLoad: $e');
    if (mounted) setState(() => _isInitialLoading = false);
  }
}

  // ========================================================================
  // PAGINATION
  // ========================================================================

  Future<void> _loadNextPage() async {
  final favoriteProvider =
      Provider.of<FavoriteProvider>(context, listen: false);

  if (favoriteProvider.isLoadingMore) return;

  // ✅ FIX: If no more data and list is empty, immediately hide shimmer
  if (!favoriteProvider.hasMoreData) {
    if (_isInitialLoading && mounted) {
      setState(() => _isInitialLoading = false);
      _loadingTimeoutTimer?.cancel();
      debugPrint('✅ No more data - shimmer hidden');
    }
    return;
  }

  try {
    final result = await favoriteProvider.loadNextPage(limit: _pageSize);

    final docs = result['docs'] as List<DocumentSnapshot>?;
    final hasMore = result['hasMore'] as bool? ?? false;
    final productIds = result['productIds'] as Set<String>?;
    final error = result['error'];

    if (error != null) {
      debugPrint('Error loading page: $error');
      if (mounted) setState(() => _isInitialLoading = false);
      _loadingTimeoutTimer?.cancel();
      return;
    }

    if (docs == null || docs.isEmpty) {
      if (mounted) {
        setState(() => _isInitialLoading = false);
        // Mark initial load complete even for empty results
        if (!favoriteProvider.isInitialLoadComplete) {
          favoriteProvider.markInitialLoadComplete();
        }
      }
      _loadingTimeoutTimer?.cancel();
      return;
    }

    final newItems =
        await _fetchProductDetailsForIds(productIds!.toList(), docs);

    if (mounted) {
      favoriteProvider.addPaginatedItems(newItems);
      
      // ✅ REMOVED: _selectedProducts logic (no longer needed)

      setState(() => _isInitialLoading = false);
      _loadingTimeoutTimer?.cancel();

      if (!favoriteProvider.isInitialLoadComplete) {
        favoriteProvider.markInitialLoadComplete();
      }
    }
  } catch (e) {
    debugPrint('❌ Error loading page: $e');
    if (mounted) setState(() => _isInitialLoading = false);
    _loadingTimeoutTimer?.cancel();

    _showErrorRetrySnackbar();
  }
}

  Future<List<Map<String, dynamic>>> _fetchProductDetailsForIds(
    List<String> productIds,
    List<DocumentSnapshot> favoriteDocs,
  ) async {
    if (productIds.isEmpty) return [];

    final List<Map<String, dynamic>> results = [];
    final Map<String, Map<String, dynamic>> favoriteDetailsByProductId = {};

    for (final doc in favoriteDocs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        final productId = data['productId'] as String?;
        if (productId != null) {
          favoriteDetailsByProductId[productId] =
              Map<String, dynamic>.from(data)..remove('productId');
        }
      }
    }

    // Chunk IDs for Firestore 'in' queries (max 10)
    for (var i = 0; i < productIds.length; i += 10) {
      final chunk = productIds.skip(i).take(10).toList();

      final futures = await Future.wait([
        _firestore
            .collection('products')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
        _firestore
            .collection('shop_products')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ]);

      for (final snapshot in futures) {
        for (final doc in snapshot.docs) {
          try {
            final product = Product.fromDocument(doc);
            final attributes = favoriteDetailsByProductId[doc.id] ?? {};
            results.add({
              'product': product,
              'attributes': attributes,
              'productId': doc.id,
            });
          } catch (e) {
            debugPrint('Error parsing product ${doc.id}: $e');
          }
        }
      }
    }

    return results;
  }

  // ========================================================================
  // SEARCH
  // ========================================================================

  void _onSearchChanged(String query) {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = query.toLowerCase());
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredItems(
      List<Map<String, dynamic>> allItems) {
    if (_searchQuery.isEmpty) return allItems;

    return allItems.where((item) {
      final product = item['product'] as Product;
      return product.productName.toLowerCase().contains(_searchQuery) ||
          (product.brandModel?.toLowerCase() ?? '').contains(_searchQuery);
    }).toList();
  }

  // ========================================================================
  // CART OPERATIONS
  // ========================================================================
Future<void> _addSelectedToCart() async {
  if (_isAddingToCart || _selectedProductId == null) return;

  final selectedProductId = _selectedProductId!;
  final l10n = AppLocalizations.of(context);
  
  setState(() => _isAddingToCart = true);

  try {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    // ✅ Find the selected item
    final selectedItem = favoriteProvider.paginatedFavorites.firstWhere(
      (item) => (item['product'] as Product).id == selectedProductId,
      orElse: () => <String, dynamic>{},
    );

    if (selectedItem.isEmpty) {
      _showErrorSnackbar(l10n.productNotFound);
      return;
    }

    final cachedProduct = selectedItem['product'] as Product;
    final attrs = (selectedItem['attributes'] as Map<String, dynamic>? ?? {});

    // Check if already in cart
    if (cartProvider.cartProductIds.contains(cachedProduct.id)) {
      if (mounted) {
        _showWarningSnackbar('${cachedProduct.productName} ${l10n.isAlreadyInCart}');
      }
      return;
    }

    // ✅ STEP 1: Fetch FRESH product data (parallel search)
    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('shop_products')
          .doc(cachedProduct.id)
          .get(),
      FirebaseFirestore.instance
          .collection('products')
          .doc(cachedProduct.id)
          .get(),
    ]);

    final shopProductDoc = results[0];
    final productDoc = results[1];

    DocumentSnapshot? freshProductDoc;
    if (shopProductDoc.exists) {
      freshProductDoc = shopProductDoc;
    } else if (productDoc.exists) {
      freshProductDoc = productDoc;
    }

    if (freshProductDoc == null || !freshProductDoc.exists) {
      if (mounted) {
        _showWarningSnackbar('${cachedProduct.productName} ${l10n.isNoLongerAvailable}');
      }
      return;
    }

    // ✅ Parse fresh product data
    final freshProduct = Product.fromDocument(freshProductDoc);

    // ✅ STEP 2: Check if product has options using FRESH data
    final hasColors = freshProduct.colorImages.isNotEmpty;
    final hasAttributes = freshProduct.attributes.entries.any((entry) {
      final value = entry.value;
      if (value is List) {
        return value.length > 1;
      } else if (value is String && value.isNotEmpty) {
        final options = value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        return options.length > 1;
      }
      return false;
    });

    Map<String, dynamic>? selections;

    // ✅ STEP 3: Show ProductOptionSelector ONLY if product has options
    if (hasColors || hasAttributes) {
      if (!mounted) return;

      selections = await showCupertinoModalPopup<Map<String, dynamic>?>(
        context: context,
        builder: (_) => ProductOptionSelector(
          product: freshProduct,
          isBuyNow: false,
        ),
      );

      // User cancelled
      if (selections == null || !mounted) {
        return;
      }
    }

    // ✅ STEP 4: Prepare cart data
    final quantity = selections?['quantity'] as int? ?? 
                    (attrs['quantity'] as int? ?? 1);
    final selectedColor = selections?['selectedColor'] as String? ?? 
                         attrs['selectedColor'] as String?;

    // Build clean attributes (remove internal fields)
    final clean = <String, dynamic>{};
    
    if (selections != null) {
      selections.forEach((k, v) {
        if (!['quantity', 'selectedColor', 'selectedColorImage'].contains(k)) {
          clean[k] = v;
        }
      });
    } else {
      attrs.forEach((k, v) {
        if (!['addedAt', 'selectedColorImage', 'quantity', 'selectedColor'].contains(k)) {
          clean[k] = v;
        }
      });
    }

    // ✅ OPTIMISTIC: Show success immediately and hide bottom sheet
    if (mounted) {
      setState(() => _selectedProductId = null);
      _bottomSheetController.reverse();
      _showSuccessSnackbar(l10n.addedToCart);
    }

    // ✅ STEP 5: Add FRESH product to cart in background (CartProvider handles optimistic updates)
    final result = await cartProvider.addProductToCart(
      freshProduct,
      quantity: quantity,
      selectedColor: selectedColor,
      attributes: clean.isEmpty ? null : clean,
    );

    // Only show error if it failed (success already shown)
    if (mounted && result != 'Added to cart') {
      _showErrorSnackbar(result);
    }
  } catch (e) {
    debugPrint('Error adding to cart: $e');
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar('${l10n.error}: ${e.toString()}');
    }
  } finally {
    if (mounted) setState(() => _isAddingToCart = false);
  }
}

void _removeSelectedFromFavorites() async {
  if (_selectedProductId == null) return;

  final selectedProductId = _selectedProductId!;
  final favoriteProvider =
      Provider.of<FavoriteProvider>(context, listen: false);

  try {
    // ✅ OPTIMISTIC: Remove from UI immediately
    if (mounted) {
      favoriteProvider.removePaginatedItems([selectedProductId]);
      setState(() => _selectedProductId = null);
      _bottomSheetController.reverse();
      favoriteProvider.showDebouncedRemoveFavoriteSnackbar(context);
    }

    // ✅ Delete in background
    String result = await favoriteProvider.removeMultipleFromFavorites([selectedProductId]);
    
    // If removal failed, show error
    if (mounted && result != 'Products removed from favorites') {
      _showErrorSnackbar(_localizeMessage(result));
      // Reload to restore consistent state
      _resetPaginationAndLoad();
    }
  } catch (e) {
    debugPrint('Error removing favorite: $e');
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar('${l10n.errorRemovingFavorite}: $e');
      // Reload to restore consistent state
      _resetPaginationAndLoad();
    }
  }
}

Future<void> _showTransferBasketDialog() async {
  if (_selectedProductId == null) return;

  final selectedProductId = _selectedProductId!;
  final l10n = AppLocalizations.of(context);
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return;

  try {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);
    final currentBasketId = favoriteProvider.selectedBasketId;

    // Fetch all baskets
    final basketsSnapshot = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('favorite_baskets')
        .get();

    final baskets = basketsSnapshot.docs.map((doc) {
      return {
        'id': doc.id,
        'name': doc.data()['name'] as String? ?? 'Unnamed',
      };
    }).toList();

    // ✅ Build options list
    List<Map<String, dynamic>> options = [];
    
    // Add "General/Default" option if currently in a basket
    if (currentBasketId != null) {
      options.add({
        'id': null,
        'name': l10n.general ?? 'General',
      });
    }
    
    // Add basket options (exclude current basket)
    options.addAll(
      baskets.where((basket) => basket['id'] != currentBasketId),
    );

    if (options.isEmpty) {
      _showWarningSnackbar(l10n.noFavoriteBaskets ?? 'No destination available');
      return;
    }

    if (!mounted) return;

    final brightness = Theme.of(context).brightness;
    final actionTextStyle = TextStyle(
        color: brightness == Brightness.light ? Colors.black : Colors.white);

    final selectedTarget = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text(l10n.selectFavoriteBasket ?? 'Select Destination', style: actionTextStyle),
          actions: options.map((option) {
            return CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, option['id']),
              child: Text(option['name'] as String, style: actionTextStyle),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(l10n.cancel, style: actionTextStyle),
          ),
        );
      },
    );

    // ✅ FIX: Return early if user cancelled (clicked Cancel or dismissed sheet)
    if (selectedTarget == 'cancel' || selectedTarget == null || !mounted) {
      debugPrint('🚫 Transfer cancelled by user');
      return; // Don't do optimistic update or transfer
    }

    // ✅ OPTIMISTIC UPDATE: Remove from UI immediately (only if not cancelled)
    if (mounted) {
      // Remove from local state immediately
      favoriteProvider.removePaginatedItems([selectedProductId]);
      
      setState(() => _selectedProductId = null);
      _bottomSheetController.reverse();
      _showSuccessSnackbar(l10n.transferredToBasket ?? 'Transferred successfully');
    }

    // ✅ Transfer in background
    final result = await favoriteProvider.transferToBasket(selectedProductId, selectedTarget);
    
    // If transfer failed, show error (item already removed from UI, but will reload on next refresh)
    if (mounted && result != 'Transferred successfully') {
      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar('${l10n.transferFailed}: ${_localizeMessage(result)}');
      // Optionally reload the page to restore the item
      _resetPaginationAndLoad();
    }
  } catch (e) {
    debugPrint('Error transferring to basket: $e');
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      _showErrorSnackbar('${l10n.error}: $e');
      // Reload to restore consistent state
      _resetPaginationAndLoad();
    }
  }
}
  // ========================================================================
  // SHARING
  // ========================================================================

  Future<void> _showShareDialog() async {
    final l10n = AppLocalizations.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);
    final selectedBasketId = favoriteProvider.selectedBasketId;

    try {
      final defaultFavoritesSnapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('favorites')
          .get();
      final defaultFavoritesCount = defaultFavoritesSnapshot.docs.length;

      final basketsSnapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('favorite_baskets')
          .get();

      List<Map<String, dynamic>> basketsWithCounts = [];
      for (var basketDoc in basketsSnapshot.docs) {
        final basketFavoritesSnapshot =
            await basketDoc.reference.collection('favorites').get();
        final basketData = basketDoc.data();
        basketsWithCounts.add({
          'id': basketDoc.id,
          'name': basketData['name'] ?? '',
          'count': basketFavoritesSnapshot.docs.length,
        });
      }

      final nonEmptyBaskets =
          basketsWithCounts.where((basket) => basket['count'] > 0).toList();

      if (!mounted) return;

      // Direct share if basket selected and has items
      if (selectedBasketId != null) {
        final selectedBasket = basketsWithCounts.firstWhere(
          (basket) => basket['id'] == selectedBasketId,
          orElse: () => {'count': 0},
        );

        if (selectedBasket['count'] > 0) {
          await _shareFavorites(selectedBasketId);
          return;
        } else {
          _showWarningSnackbar(l10n.noFavoritesToShare);
          return;
        }
      }

      final hasDefaultFavorites = defaultFavoritesCount > 0;
      final hasNonEmptyBaskets = nonEmptyBaskets.isNotEmpty;

      if (!hasDefaultFavorites && !hasNonEmptyBaskets) {
        _showWarningSnackbar(l10n.noFavoritesToShare);
        return;
      }

      if (hasDefaultFavorites && !hasNonEmptyBaskets) {
        await _shareFavorites(null);
        return;
      }

      if (!hasDefaultFavorites && nonEmptyBaskets.length == 1) {
        await _shareFavorites(nonEmptyBaskets.first['id']);
        return;
      }

      // Show modal with options
      final brightness = Theme.of(context).brightness;
      final actionTextStyle = TextStyle(
          color: brightness == Brightness.light ? Colors.black : Colors.white);

      List<CupertinoActionSheetAction> actions = [];

      if (hasDefaultFavorites) {
        actions.add(
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'general'),
            child: Text('${l10n.general} ($defaultFavoritesCount)',
                style: actionTextStyle),
          ),
        );
      }

      for (var basket in nonEmptyBaskets) {
        actions.add(
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, basket['id']),
            child: Text('${basket['name']} (${basket['count']})',
                style: actionTextStyle),
          ),
        );
      }

      final selectedBasketIdFromModal = await showCupertinoModalPopup<String?>(
        context: context,
        builder: (BuildContext context) {
          return CupertinoActionSheet(
            title: Text(l10n.selectFavoritesToShare, style: actionTextStyle),
            actions: actions,
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text(l10n.cancel, style: actionTextStyle),
            ),
          );
        },
      );

      if (selectedBasketIdFromModal == 'cancel' ||
          selectedBasketIdFromModal == null ||
          !mounted) return;

      final basketIdToShare = selectedBasketIdFromModal == 'general'
          ? null
          : selectedBasketIdFromModal;
      await _shareFavorites(basketIdToShare);
    } catch (e) {
      debugPrint('Error showing share dialog: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        _showErrorSnackbar('${l10n.error}: $e');
      }
    }
  }

  Future<void> _shareFavorites(String? basketId) async {
    final l10n = AppLocalizations.of(context);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );

      final senderName = currentUser.displayName ?? 'Anonymous';
      final shareUrl = await FavoritesSharingService.shareFavorites(
        basketId: basketId,
        senderName: senderName,
        context: context,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (shareUrl != null && shareUrl.trim().isNotEmpty) {
        final shareId = shareUrl.split('/').last;
        final sharedData =
            await FavoritesSharingService.getSharedFavorites(shareId);

        if (sharedData != null) {
          final shareTitle =
              (sharedData['shareTitle'] as String? ?? 'Shared Favorites')
                  .trim();
          final basketName =
              (sharedData['basketName'] as String? ?? 'General').trim();
          final itemCount = sharedData['itemCount'] as int? ?? 0;
          final languageCode =
              (sharedData['languageCode'] as String? ?? 'tr').trim();

          final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
          final Rect? sharePositionOrigin = renderBox != null
              ? renderBox.localToGlobal(Offset.zero) & renderBox.size
              : null;

          final shareResult = await FavoritesSharingService.shareWithRichContent(
            shareTitle: shareTitle,
            shareUrl: shareUrl,
            senderName:
                senderName.trim().isEmpty ? 'Someone' : senderName.trim(),
            basketName: basketName,
            itemCount: itemCount,
            languageCode: languageCode,
            sharePositionOrigin: sharePositionOrigin,
            context: context,
          );

          // Only show success if user actually shared (not dismissed)
          if (mounted && shareResult?.status == ShareResultStatus.success) {
            _showSuccessSnackbar(
                l10n.favoritesShared ?? 'Favorites shared successfully!');
          }
        } else {
          // Fallback
          final shareResult = await Share.share(shareUrl);
          // Only show success if user actually shared (not dismissed)
          if (mounted && shareResult.status == ShareResultStatus.success) {
            _showSuccessSnackbar(
                l10n.favoritesShared ?? 'Favorites shared successfully!');
          }
        }
      } else {
        if (mounted) {
          _showErrorSnackbar(
              l10n.errorImportingFavorites ?? 'Error sharing favorites');
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorSnackbar('${l10n.errorImportingFavorites ?? "Error"}: $e');
      }
      debugPrint('Error sharing favorites: $e');
    }
  }

  // ========================================================================
  // UI HELPERS
  // ========================================================================

  String _localizeMessage(String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'pleaseLoginFirst':
        return l10n.pleaseLoginFirst;
      case 'noProductsSelected':
        return l10n.noProductsSelected;
      case 'pleaseWait':
        return l10n.pleaseWait;
      case 'productsRemovedFromFavorites':
        return l10n.productsRemovedFromFavorites;
      case 'errorRemovingFavorites':
        return l10n.errorRemovingFavorites;
      case 'itemNotFound':
        return l10n.itemNotFound;
      case 'errorTransferringItem':
        return l10n.errorTransferringItem;
      case 'maximumBasketLimit':
        return l10n.maximumBasketLimit;
      case 'errorCreatingBasket':
        return l10n.errorCreatingBasket;
      case 'errorDeletingBasket':
        return l10n.errorDeletingBasket;
      default:
        return key;
    }
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorRetrySnackbar() {
    final favoriteProvider =
        Provider.of<FavoriteProvider>(context, listen: false);

    if (favoriteProvider.paginatedFavorites.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).failedToLoadFavorites),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: AppLocalizations.of(context).retry,
            textColor: Colors.white,
            onPressed: () => _resetPaginationAndLoad(),
          ),
        ),
      );
    }
  }

  // ========================================================================
  // UI WIDGETS
  // ========================================================================

  Widget _buildBottomAction(AppLocalizations l10n) {
  return Row(
    children: [
      // Remove button
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _removeSelectedFromFavorites,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l10n.remove ?? 'Remove'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),

      // Transfer button
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _showTransferBasketDialog,
          icon: const Icon(Icons.move_to_inbox, size: 18),
          label: Text(l10n.transferToBasket ?? 'Transfer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A86B), // Jade green
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),

      // Add to cart button
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _addSelectedToCart,
          icon: const Icon(Icons.shopping_cart_outlined, size: 18),
          label: Text(l10n.addToCart),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      ),
    ],
  );
}

  Widget _buildAuthPrompt(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty-product2.png',
              width: 150,
              height: 150,
              color: isDark ? Colors.white.withOpacity(0.3) : null,
              colorBlendMode: isDark ? BlendMode.srcATop : null,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noLoggedInForFavorites,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => context.push('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            l10n.login2,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => context.push('/register'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                            ),
                          ),
                          child: Text(
                            l10n.register,
                            style: GoogleFonts.inter(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
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
    );
  }

  Widget _buildSearchBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: l10n.searchFavorites ?? 'Search favorites...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _onSearchChanged(''),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSelectableFavoriteItem(
    Map<String, dynamic> favoriteItem, int index) {
  final product = favoriteItem['product'] as Product;
  final attributes =
      favoriteItem['attributes'] as Map<String, dynamic>? ?? {};

  final selectedColorImage = attributes['selectedColorImage'] as String?;
  final selectedColor = attributes['selectedColor'] as String?;

  final favoriteProvider =
      Provider.of<FavoriteProvider>(context, listen: false);

  // ✅ FIXED: Check if THIS item is selected
  final isSelected = _selectedProductId == product.id;

  return LayoutBuilder(builder: (ctx, constraints) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ✅ FIXED: Checkbox for selection
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            isSelected ? Icons.check_circle : Icons.check_circle_outline,
            color: isSelected ? const Color(0xFF00A86B) : Colors.grey,
            size: 24,
          ),
          onPressed: () {
            setState(() {
              // Toggle: if already selected, deselect; otherwise select this one
              if (_selectedProductId == product.id) {
                _selectedProductId = null;
                _bottomSheetController.reverse();
              } else {
                _selectedProductId = product.id;
                _bottomSheetController.forward();
              }
            });
          },
        ),
        const SizedBox(width: 8),
        
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable:
                favoriteProvider.getFavoriteStatusNotifier(product.id),
            builder: (context, isFavorited, child) {
              return RepaintBoundary(
                child: GestureDetector(
                  onTap: () => context.push('/product/${product.id}'),
                  child: ProductCard4(
                    imageUrl: selectedColorImage ??
                        (product.imageUrls.isNotEmpty
                            ? product.imageUrls.first
                            : ''),
                    colorImages: product.colorImages,
                    selectedColor: selectedColor,
                    productName: product.productName,
                    brandModel: product.brandModel ?? '',
                    price: product.price,
                    currency: product.currency,
                    averageRating: product.averageRating,
                    scaleFactor: 1.0,
                    showOverlayIcons: false,
                    productId: product.id,
                    originalPrice: product.originalPrice,
                    discountPercentage: product.discountPercentage,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  });
}

 Widget _buildBody(BuildContext context, AppLocalizations l10n) {
  final favoriteProvider = Provider.of<FavoriteProvider>(context, listen: false);

  return ValueListenableBuilder<List<Map<String, dynamic>>>(
    valueListenable: favoriteProvider.paginatedFavoritesNotifier,
    builder: (context, allItems, _) {
      final displayedItems = _getFilteredItems(allItems);

      // ✅ FIX: Show shimmer only if loading AND we haven't determined the list is empty yet
      // Once we know the list is empty (allItems.isEmpty and !hasMoreData), show empty state immediately
      final shouldShowShimmer = _isInitialLoading &&
                               (allItems.isNotEmpty || favoriteProvider.hasMoreData);

      if (shouldShowShimmer) {
        return ListView.separated(
          padding: const EdgeInsets.all(8.0),
          itemCount: 8,
          separatorBuilder: (context, index) => Column(
            children: [
              const SizedBox(height: 8.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Divider(
                  color: Colors.grey[300],
                  thickness: 1.0,
                  height: 16.0,
                ),
              ),
            ],
          ),
          itemBuilder: (context, index) => const ProductCard4Shimmer(),
        );
      }

      return ValueListenableBuilder<bool>(
        valueListenable: favoriteProvider.hasMoreDataNotifier,
        builder: (context, hasMoreData, _) {
          if (displayedItems.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/images/empty-product2.png',
                        width: 130,
                        height: 130,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      l10n.discoverProducts,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 200,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final marketScreenState = context
                                  .findAncestorStateOfType<State<MarketScreen>>()
                              as MarketScreenState?;
                          marketScreenState?.navigateToTab(1);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0)),
                        ),
                        child: Text(
                          l10n.discover,
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= displayedItems.length) {
                      return hasMoreData
                          ? Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  const ProductCard4Shimmer(),
                                  const SizedBox(height: 8.0),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    child: Divider(
                                      color: Colors.grey[300],
                                      thickness: 1.0,
                                      height: 16.0,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink();
                    }

                    final favoriteItem = displayedItems[index];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RepaintBoundary(
                          key: ValueKey((favoriteItem['product'] as Product).id),
                          child:
                              _buildSelectableFavoriteItem(favoriteItem, index),
                        ),
                        if (index < displayedItems.length - 1) ...[
                          const SizedBox(height: 8.0),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Divider(
                                color: Colors.grey[300],
                                thickness: 1.0,
                                height: 16.0),
                          ),
                        ],
                      ],
                    );
                  },
                  childCount: displayedItems.length + (hasMoreData ? 1 : 0),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      );
    },
  );
}

 AppBar _buildAppBar(AppLocalizations l10n) {
  final favoriteProvider =
      Provider.of<FavoriteProvider>(context, listen: false);

  return AppBar(
    automaticallyImplyLeading: false,
    title: ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: favoriteProvider.paginatedFavoritesNotifier,
      builder: (context, items, child) {
        final totalCount = items.length;
        return Text(
          '${l10n.myFavorites} ${favoriteProvider.hasMoreData ? "($totalCount+)" : "($totalCount)"}',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        );
      },
    ),
    centerTitle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    elevation: 0,
    actions: [
      IconButton(
        icon: const Icon(Icons.share),
        onPressed: _showShareDialog,
      ),
    ],
  );
}

  // ========================================================================
  // BUILD
  // ========================================================================

 @override
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          l10n.myFavorites,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: _buildAuthPrompt(l10n),
      ),
    );
  }

  return Scaffold(
    appBar: _buildAppBar(l10n),
    body: SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          FavoriteBasketWidget(
            onBasketChanged: () {
              final favoriteProvider =
                  Provider.of<FavoriteProvider>(context, listen: false);
              if (favoriteProvider
                  .shouldReloadFavorites(favoriteProvider.selectedBasketId)) {
                _resetPaginationAndLoad();
              }
              // Clear selection on basket change
              if (mounted) {
                setState(() => _selectedProductId = null);
                _bottomSheetController.reverse();
              }
            },
          ),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable:
                Provider.of<FavoriteProvider>(context, listen: false)
                    .paginatedFavoritesNotifier,
            builder: (context, items, child) {
              return items.length > 20
                  ? _buildSearchBar(l10n)
                  : const SizedBox.shrink();
            },
          ),
          Expanded(child: _buildBody(context, l10n)),
        ],
      ),
    ),
    // ✅ ADD BACK: Bottom sheet (shows when item selected)
    bottomSheet: _selectedProductId != null
        ? SlideTransition(
            position: _bottomSheetAnimation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: _buildBottomAction(l10n),
              ),
            ),
          )
        : null,
  );
}

  // ========================================================================
  // DISPOSE
  // ========================================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);    
    _authSubscription?.cancel();
    _scrollController.dispose();
    _searchDebouncer?.cancel();
    _loadingTimeoutTimer?.cancel();
    _bottomSheetController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }
}
