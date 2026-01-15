// lib/screens/boost_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'boost_payment_webview.dart';

// Import localization
import '../../generated/l10n/app_localizations.dart';
// Import BoostAnalysisScreen so we can navigate to it

class BoostPricesService {
  static final BoostPricesService _instance = BoostPricesService._internal();
  factory BoostPricesService() => _instance;
  BoostPricesService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cached values
  double _pricePerProductPerMinute = 1.0;
  int _minDuration = 5;
  int _maxDuration = 35;
  int _maxProducts = 5;
  bool _serviceEnabled = true;

  StreamSubscription<DocumentSnapshot>? _subscription;
  final _configController = StreamController<void>.broadcast();

  // Getters
  double get pricePerProductPerMinute => _pricePerProductPerMinute;
  int get minDuration => _minDuration;
  int get maxDuration => _maxDuration;
  int get maxProducts => _maxProducts;
  bool get serviceEnabled => _serviceEnabled;
  Stream<void> get configStream => _configController.stream;

  // Generate duration options dynamically
  List<int> get durationOptions {
    final List<int> options = [];
    for (int i = _minDuration; i <= _maxDuration; i += 5) {
      options.add(i);
    }
    if (options.isEmpty) options.add(_minDuration);
    return options;
  }

  void startListening() {
    if (_subscription != null) return;

    _subscription = _firestore
        .collection('app_config')
        .doc('boost_prices')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        _pricePerProductPerMinute =
            (data['pricePerProductPerMinute'] ?? 1.0).toDouble();
        _minDuration = (data['minDuration'] ?? 5).toInt();
        _maxDuration = (data['maxDuration'] ?? 35).toInt();
        _maxProducts = (data['maxProducts'] ?? 5).toInt();
        _serviceEnabled = data['serviceEnabled'] ?? true;
        _configController.add(null);
      } else {
        // Use defaults
        _pricePerProductPerMinute = 1.0;
        _minDuration = 5;
        _maxDuration = 35;
        _maxProducts = 5;
        _serviceEnabled = true;
        _configController.add(null);
      }
    }, onError: (e) {
      debugPrint('Error listening to boost prices: $e');
      _configController.add(null);
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}

class BoostScreen extends StatefulWidget {
  final String? productId;
  final bool isShopContext;
  final String? shopId;

  const BoostScreen({
    Key? key,
    this.productId,
    this.isShopContext = false,
    this.shopId,
  }) : super(key: key);

  @override
  _BoostScreenState createState() => _BoostScreenState();
}

class _BoostScreenState extends State<BoostScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Main item to be boosted (if provided)
  Map<String, dynamic>? itemData;
  String? _itemType; // Only 'product' is supported now.
  // _itemType remains null if no main item is provided.

  // Pricing: now the base price is 150 TL per product per day.
  double basePricePerProduct = 1.0;
  int boostDuration = 5; // in minutes (default)
  double totalPrice = 5.0; // boostDuration * basePricePerProduct * (item count)

  final BoostPricesService _boostPricesService = BoostPricesService();
  StreamSubscription<void>? _pricesSubscription;

  // Although bulk boost previously used a TabBar (with one tab),
  // we are now removing the l10n.product tab.
  // We keep _tabController here to preserve similar code structure.
  late TabController _tabController;

  // Products (unboosted)
  List<Map<String, dynamic>> _unboostedProducts = [];

  // Items the user selected from the list
  List<String> selectedItemIds = [];

  // Jade green color => 0xFF00A86B
  final Color jadeGreen = const Color(0xFF00A86B);

  // Boost duration options: now in minutes from 5 to 35.

  int selectedDurationIndex = 0; // default to index 0 => 5 minutes

  @override
  void initState() {
    super.initState();
    _determineItemType();

    // ADD: Start listening to boost prices
    _boostPricesService.startListening();
    _pricesSubscription = _boostPricesService.configStream.listen((_) {
      if (mounted) {
        // Update duration options if current selection is out of range
        final options = _boostPricesService.durationOptions;
        if (selectedDurationIndex >= options.length) {
          selectedDurationIndex = 0;
        }
        boostDuration = options[selectedDurationIndex];
        _updateTotalPrice();
        setState(() {});
      }
    });

    _tabController = TabController(length: 1, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final futures = <Future>[];
      if (_itemType != null) {
        futures.add(_fetchItemData());
      }
      futures.add(_fetchUnboostedItems());
      await Future.wait(futures);
      _updateTotalPrice();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pricesSubscription?.cancel(); // ADD this
    super.dispose();
  }

  void _determineItemType() {
    if (widget.productId != null) {
      _itemType = 'product';
    } else {
      // No main item provided; operate in bulk boost mode.
      _itemType = null;
    }
  }

  /// Fetch the main product's data (if applicable).
  Future<void> _fetchItemData() async {
    if (_itemType == null) return; // Nothing to fetch.
    try {
      // Start both collection queries in parallel
      final futures = [
        _firestore.collection('products').doc(widget.productId).get(),
        _firestore.collection('shop_products').doc(widget.productId).get(),
      ];

      final results = await Future.wait(futures);

      // Find the first existing document
      DocumentSnapshot? doc;
      String? collection;
      for (var i = 0; i < results.length; i++) {
        if (results[i].exists) {
          doc = results[i];
          collection = i == 0 ? 'products' : 'shop_products';
          break;
        }
      }

      if (doc == null) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.itemNotFound,
              style: const TextStyle(fontFamily: 'Figtree'),
            ),
          ),
        );
        Navigator.pop(context);
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      String imageUrl =
          (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty)
              ? data['imageUrls'][0]
              : '';

      setState(() {
        itemData = data;
        itemData!['imageUrl'] = imageUrl;
        itemData!['collection'] = collection; // Add collection information
        // Update total price for main item.
        totalPrice = boostDuration * basePricePerProduct;
      });
    } catch (e) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.errorOccurred}: $e',
            style: const TextStyle(fontFamily: 'Figtree'),
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  /// Fetch unboosted products for bulk boosting.
  Future<void> _fetchUnboostedItems() async {
    final user = _auth.currentUser;
    if (user == null) return;

    Query<Map<String, dynamic>> query;
    if (widget.isShopContext && widget.shopId != null) {
      // only that shop's products
      query = _firestore
          .collection('shop_products')
          .where('shopId', isEqualTo: widget.shopId)
          .where('isBoosted', isEqualTo: false)
          .orderBy('createdAt', descending: true);
    } else {
      // only the user's own products
      query = _firestore
          .collection('products')
          .where('userId', isEqualTo: user.uid)
          .where('isBoosted', isEqualTo: false)
          .orderBy('createdAt', descending: true);
    }

    final snapshot = await query.get();
    final list = snapshot.docs.map((doc) {
      final data = doc.data();
      data['itemId'] = doc.id;
      data['collection'] = widget.isShopContext ? 'shop_products' : 'products';
      data['imageUrl'] = (data['imageUrls'] as List).isNotEmpty
          ? (data['imageUrls'] as List).first
          : '';
      return data;
    }).toList();

    // if you had a main product, remove it from that list
    if (widget.productId != null) {
      list.removeWhere((m) => m['itemId'] == widget.productId);
    }

    setState(() {
      _unboostedProducts = list;
    });
  }

  /// Returns the display name for a product.
  String _getItemDisplayName(Map<String, dynamic> data, String type) {
    final l10n = AppLocalizations.of(context);
    return data['productName'] ?? l10n.unnamed;
  }

  /// Check if user has any products to boost
  bool get hasProductsToBoost {
    if (!_boostPricesService.serviceEnabled) return false; // ADD this check
    return (_itemType != null) ||
        _unboostedProducts.isNotEmpty ||
        selectedItemIds.isNotEmpty;
  }

  /// Build info banner at the top
  Widget _buildInfoBanner() {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            jadeGreen.withOpacity(0.1),
            jadeGreen.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: jadeGreen.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: jadeGreen.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.rocket_launch_rounded,
              color: jadeGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.boostInfoTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isLightMode ? Colors.grey[800] : Colors.grey[100],
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.boostInfoDescription,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLightMode ? Colors.grey[600] : Colors.grey[300],
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build empty state when user has no products to boost
  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isLightMode
                    ? Colors.grey[100]
                    : const Color.fromARGB(255, 45, 43, 61),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                size: 64,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noProductsToBoostTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isLightMode ? Colors.grey[800] : Colors.grey[200],
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noProductsToBoostDescription,
              style: TextStyle(
                fontSize: 14,
                color: isLightMode ? Colors.grey[600] : Colors.grey[400],
                fontFamily: 'Inter',
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [jadeGreen, jadeGreen.withOpacity(0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          l10n.addProductFirst,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCheckTile(
    Map<String, dynamic> data,
    String type,
  ) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final itemId = data['itemId'] ?? '';
    final isSelected = selectedItemIds.contains(itemId);
    final l10n = AppLocalizations.of(context);

    final itemName = _getItemDisplayName(data, type);
    final imageUrl = data['imageUrl'] ?? '';

    // Calculate total items that would be selected
    final int totalItemsCount =
        (_itemType != null ? 1 : 0) + selectedItemIds.length;
    final bool canSelectMore =
        totalItemsCount < _boostPricesService.maxProducts;

    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      decoration: BoxDecoration(
        color: isSelected
            ? jadeGreen.withOpacity(0.1)
            : (isLightMode
                ? Colors.white
                : const Color.fromARGB(255, 33, 31, 49)),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isSelected
              ? jadeGreen.withOpacity(0.3)
              : (isLightMode ? Colors.grey[200]! : Colors.grey[700]!),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color:
                (isLightMode ? Colors.black : Colors.white).withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: () {
            setState(() {
              if (isSelected) {
                // Always allow deselection
                selectedItemIds.remove(itemId);
              } else {
                // Check limit before adding
                if (canSelectMore) {
                  selectedItemIds.add(itemId);
                } else {
                  // Show limit reached message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.maximumProductsCanBeBoostedAtOnce,
                        style: const TextStyle(fontFamily: 'Figtree'),
                      ),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
              _updateTotalPrice();
            });
          },
          child: Opacity(
            opacity: (!isSelected && !canSelectMore) ? 0.4 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  // Custom checkbox
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? jadeGreen : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? jadeGreen : Colors.grey[400]!,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image,
                                  size: 20, color: Colors.grey),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image,
                                  size: 20, color: Colors.grey),
                            ),
                          )
                        : Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Icon(Icons.image_not_supported,
                                size: 20, color: Colors.grey),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: Text(
                      itemName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Figtree',
                        color:
                            isLightMode ? Colors.grey[800] : Colors.grey[200],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Single product (the main item) preview section.
  /// If no main product was passed, returns an empty container.
  Widget _buildSingleBoostSection() {
    if (_itemType == null) {
      return Container();
    }
    if (itemData == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final l10n = AppLocalizations.of(context);

    // Tablet detection
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth >= 600;

    // Tablet: 1/4 width, Mobile: half width
    final double cardWidth = isTablet ? screenWidth * 0.25 : screenWidth * 0.5;
    // Tablet: taller image, Mobile: taller image for better visibility
    final double imageHeight = isTablet ? 160.0 : 160.0;

    String displayName = _getItemDisplayName(itemData!, _itemType!);
    String imageUrl = itemData!['imageUrl'] ?? '';

    final cardWidget = Container(
      width: cardWidth,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color:
            isLightMode ? Colors.white : const Color.fromARGB(255, 33, 31, 49),
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color:
                (isLightMode ? Colors.black : Colors.white).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16.0),
              topRight: Radius.circular(16.0),
            ),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    height: imageHeight,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: imageHeight,
                      color: Colors.grey[200],
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: imageHeight,
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.image_not_supported,
                        size: 32,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : Container(
                    height: imageHeight,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 32,
                      color: Colors.grey,
                    ),
                  ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Figtree',
                    color: isLightMode ? Colors.grey[800] : Colors.grey[100],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: jadeGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: jadeGreen.withOpacity(0.3)),
                  ),
                  child: Text(
                    l10n.primaryItem,
                    style: TextStyle(
                      fontSize: isTablet ? 10 : 11,
                      fontWeight: FontWeight.w600,
                      color: jadeGreen,
                      fontFamily: 'Figtree',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Align the card to start (left) since it's now half-width
    return Align(
      alignment: Alignment.centerLeft,
      child: cardWidget,
    );
  }

  Widget _buildTabBarSection() {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final int totalSelected =
        (_itemType != null ? 1 : 0) + selectedItemIds.length;
    final int maxProducts =
        _boostPricesService.maxProducts; // Add this for cleaner code

    return Column(
      children: [
        // Selection counter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: totalSelected >= maxProducts
                ? Colors.orange.withOpacity(0.1)
                : jadeGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: totalSelected >= maxProducts
                  ? Colors.orange.withOpacity(0.3) // ← Also fix this (was 0.1)
                  : jadeGreen.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                totalSelected >= maxProducts
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 16,
                color: totalSelected >= maxProducts ? Colors.orange : jadeGreen,
              ),
              const SizedBox(width: 8),
              Text(
                '$totalSelected / $maxProducts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      totalSelected >= maxProducts ? Colors.orange : jadeGreen,
                  fontFamily: 'Figtree',
                ),
              ),
            ],
          ),
        ),

        // Existing list
        SizedBox(
          height: 260,
          child: _buildTabListView(
            _unboostedProducts,
            'product',
          ),
        ),
      ],
    );
  }

  /// Reusable ListView builder for products.
  Widget _buildTabListView(
    List<Map<String, dynamic>> items,
    String type,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).noMoreItemsToAdd,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (_, index) {
        final data = items[index];
        return _buildItemCheckTile(data, type);
      },
    );
  }

  void _updateTotalPrice() {
    final int itemCount = (_itemType != null ? 1 : 0) + selectedItemIds.length;
    setState(() {
      totalPrice = boostDuration *
          _boostPricesService.pricePerProductPerMinute *
          itemCount;
    });
  }

  /// Returns a formatted duration label in minutes.
  String _getDurationLabel(int minutes) {
    final l10n = AppLocalizations.of(context);
    return '$minutes ${l10n.minutes}';
  }

  Future<void> _proceedToPayment() async {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.userNotAuthenticated)),
      );
      return;
    }

    // Prepare items
    final List<Map<String, dynamic>> items = [];

    // Add main item if exists
    if (_itemType != null && itemData != null) {
      items.add({
        'itemId': widget.productId!,
        'collection': itemData!['collection'],
        'shopId': itemData!['shopId'],
      });
    }

    // Add selected items
    for (String itemId in selectedItemIds) {
      final found = _unboostedProducts.firstWhere(
        (element) => element['itemId'] == itemId,
        orElse: () => {},
      );
      if (found.isNotEmpty) {
        items.add({
          'itemId': itemId,
          'collection': found['collection'],
          'shopId': found['shopId'],
        });
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noItemToBoost)),
      );
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (ctx) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: isLightMode
                            ? Colors.white
                            : const Color(0xFF2D2B3D),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Animated progress indicator with gradient ring
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  jadeGreen.withOpacity(0.1),
                                  jadeGreen.withOpacity(0.05),
                                ],
                              ),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(jadeGreen),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Animated linear progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: double.infinity,
                              height: 6,
                              child: TweenAnimationBuilder<double>(
                                duration: const Duration(seconds: 2),
                                tween: Tween(begin: 0.0, end: 1.0),
                                builder: (context, progress, child) {
                                  return LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: (isLightMode
                                        ? Colors.grey[200]
                                        : Colors.grey[700]),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        jadeGreen),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            l10n.preparingPayment,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isLightMode
                                  ? Colors.grey[800]
                                  : Colors.grey[100],
                              fontFamily: 'Figtree',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.pleaseWait,
                            style: TextStyle(
                              fontSize: 14,
                              color: isLightMode
                                  ? Colors.grey[600]
                                  : Colors.grey[400],
                              fontFamily: 'Figtree',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Get user info for payment
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      // Initialize payment
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('initializeBoostPayment');

      final result = await callable.call({
        'items': items,
        'boostDuration': boostDuration,
        'isShopContext': widget.isShopContext,
        'shopId': widget.shopId,
        'customerName':
            userData['displayName'] ?? userData['name'] ?? 'Customer',
        'customerEmail': userData['email'] ?? user.email ?? '',
        'customerPhone': userData['phone'] ?? '',
      });

      Navigator.of(context).pop(); // Close loading dialog

      final responseData = Map<String, dynamic>.from(result.data as Map);
      if (responseData['success'] == true) {
        final gatewayUrl = responseData['gatewayUrl'] as String;
        final paymentParams =
            Map<String, dynamic>.from(responseData['paymentParams'] as Map);
        final orderNumber = responseData['orderNumber'] as String;

        // Navigate to payment webview
        final paymentResult = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => BoostPaymentWebView(
              gatewayUrl: gatewayUrl,
              paymentParams: paymentParams,
              orderNumber: orderNumber,
            ),
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog if open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  /// "Complete Payment" button.
  Widget _buildCompletePaymentButton() {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [jadeGreen, jadeGreen.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _proceedToPayment,
          child: Container(
            width: double.infinity,
            height: 52,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payment_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  l10n.completePayment,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Figtree',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final Color textAndBorderColor =
        isLightMode ? Colors.grey[800]! : Colors.grey[200]!;

    return Scaffold(
      backgroundColor: isLightMode
          ? const Color.fromARGB(255, 244, 244, 244)
          : const Color(0xFF1C1A29),
      appBar: AppBar(
        elevation: 0,
        title: Text(
          l10n.ads,
          style: TextStyle(
            color: textAndBorderColor,
            fontWeight: FontWeight.w700,
            fontFamily: 'Figtree',
            fontSize: 18,
          ),
        ),
        backgroundColor: isLightMode
            ? const Color.fromARGB(255, 244, 244, 244)
            : const Color(0xFF1C1A29),
        iconTheme: IconThemeData(color: textAndBorderColor),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              decoration: BoxDecoration(
                color: isLightMode
                    ? Colors.white
                    : const Color.fromARGB(255, 33, 31, 49),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: textAndBorderColor.withOpacity(0.2)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    context.push('/boost-analysis');
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          color: textAndBorderColor,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.analytics,
                          style: TextStyle(
                            color: textAndBorderColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner at the top
                  _buildInfoBanner(),

                  if (!_boostPricesService.serviceEnabled) ...[
                    _buildServiceDisabledState(),
                  ] else if (!hasProductsToBoost) ...[
                    _buildEmptyState(),
                  ] else ...[
                    // Single boost section
                    _buildSingleBoostSection(),

                    // Add more items section
                    if (_unboostedProducts.isNotEmpty || _itemType == null) ...[
                      Text(
                        l10n.addMoreItems,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textAndBorderColor,
                          fontFamily: 'Figtree',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTabBarSection(),
                      const SizedBox(height: 20),
                    ],

                    // Duration section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isLightMode
                            ? Colors.white
                            : const Color.fromARGB(255, 33, 31, 49),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (isLightMode ? Colors.black : Colors.white)
                                .withOpacity(0.05),
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
                              Icon(
                                Icons.schedule_rounded,
                                size: 20,
                                color: jadeGreen,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.selectBoostDuration,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: textAndBorderColor,
                                  fontFamily: 'Figtree',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: jadeGreen,
                              inactiveTrackColor: Colors.grey[300],
                              thumbColor: jadeGreen,
                              overlayColor: jadeGreen.withOpacity(0.2),
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 10),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 20),
                            ),
                            child: Slider(
                              value: selectedDurationIndex.toDouble(),
                              min: 0,
                              max: (_boostPricesService.durationOptions.length -
                                      1)
                                  .toDouble(),
                              divisions:
                                  _boostPricesService.durationOptions.length -
                                      1,
                              label: _getDurationLabel(_boostPricesService
                                  .durationOptions[selectedDurationIndex]),
                              onChanged: (double value) {
                                setState(() {
                                  selectedDurationIndex = value.toInt();
                                  boostDuration = _boostPricesService
                                      .durationOptions[selectedDurationIndex];
                                  _updateTotalPrice();
                                });
                              },
                            ),
                          ),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: jadeGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: jadeGreen.withOpacity(0.3)),
                              ),
                              child: Text(
                                _getDurationLabel(boostDuration),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: jadeGreen,
                                  fontFamily: 'Figtree',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Price section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withOpacity(0.1),
                            Colors.pink.withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            l10n.totalPriceLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textAndBorderColor.withOpacity(0.7),
                              fontFamily: 'Figtree',
                            ),
                          ),
                          const SizedBox(height: 8),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.orange, Colors.pink],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              '${totalPrice.toStringAsFixed(2)} TL',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontFamily: 'Figtree',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Only show payment button if user has products to boost
          if (hasProductsToBoost)
            SafeArea(
              top: false,
              child: Builder(
                builder: (context) {
                  // Tablet detection for button width
                  final screenWidth = MediaQuery.of(context).size.width;
                  final bool isTablet = screenWidth >= 600;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.transparent,
                    child: isTablet
                        ? Center(
                            child: SizedBox(
                              width: screenWidth * 0.5, // Half width on tablet
                              child: _buildCompletePaymentButton(),
                            ),
                          )
                        : _buildCompletePaymentButton(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceDisabledState() {
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.pause_circle_outline_rounded,
                size: 64,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.boostServiceTemporarilyOff,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isLightMode ? Colors.grey[800] : Colors.grey[200],
                fontFamily: 'Inter',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.boostServiceDisabledMessage,
              style: TextStyle(
                fontSize: 14,
                color: isLightMode ? Colors.grey[600] : Colors.grey[400],
                fontFamily: 'Inter',
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
