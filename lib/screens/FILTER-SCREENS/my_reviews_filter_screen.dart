import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';

class MyReviewsFilterScreen extends StatefulWidget {
  final String userId;
  final bool isShopProduct;
  final String? initialProductId;
  final String? initialSellerId;

  const MyReviewsFilterScreen({
    Key? key,
    required this.userId,
    required this.isShopProduct,
    this.initialProductId,
    this.initialSellerId,
  }) : super(key: key);

  @override
  _MyReviewsFilterScreenState createState() => _MyReviewsFilterScreenState();
}

class _MyReviewsFilterScreenState extends State<MyReviewsFilterScreen> {
  bool _isProductExpanded = false;
  bool _isSellerExpanded = false;
  late ScrollController _productScrollController;
  late ScrollController _sellerScrollController;

  String? _selectedProductId;
  String? _selectedSellerId;

  static const int _pageSize = 20;
  DocumentSnapshot<Map<String, dynamic>>? _lastProductDoc;
  DocumentSnapshot<Map<String, dynamic>>? _lastSellerDoc;
  bool _hasMoreProducts = true;
  bool _hasMoreSellers = true;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sellers = [];
  bool _loadingProducts = true;
  bool _loadingSellers = true;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    _selectedSellerId = widget.initialSellerId;

    _productScrollController = ScrollController();
    _sellerScrollController = ScrollController();
    _productScrollController.addListener(_onProductScroll);
    _sellerScrollController.addListener(_onSellerScroll);

    _loadProducts();
    _loadSellers();
  }

  @override
  void dispose() {
    _productScrollController.dispose();
    _sellerScrollController.dispose();
    super.dispose();
  }

  void _onProductScroll() {
    final pos = _productScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_loadingProducts &&
        _hasMoreProducts) {
      _loadProducts();
    }
  }

  void _onSellerScroll() {
    final pos = _sellerScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_loadingSellers &&
        _hasMoreSellers) {
      _loadSellers();
    }
  }

  /// Validates if a URL is valid for network image loading
  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;

    try {
      final uri = Uri.parse(url.trim());
      return uri.hasScheme &&
          uri.host.isNotEmpty &&
          (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadProducts() async {
    if (!_hasMoreProducts) return;

    setState(() => _loadingProducts = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collectionGroup('reviews')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (_lastProductDoc != null) {
        q = q.startAfterDocument(_lastProductDoc!);
      }

      final snap = await q.get();

      if (snap.docs.length < _pageSize) {
        _hasMoreProducts = false;
      }
      if (snap.docs.isNotEmpty) {
        _lastProductDoc = snap.docs.last;
      }

      final byId = <String, Map<String, dynamic>>{
        for (var p in _products) p['id'] as String: p
      };

      for (var doc in snap.docs) {
        final d = doc.data();
        final String? pid = d['productId'] as String?;
        if (pid == null || pid.trim().isEmpty) continue;

        if (!byId.containsKey(pid)) {
          // Get the best image URL (color-specific if available)
          String imageUrl = d['productImage'] as String? ?? '';
          final selectedColor = d['selectedColor'] as String?;
          final colorImages = d['colorImages'] as Map<String, dynamic>?;

          if (selectedColor != null && colorImages != null) {
            final colorImageList = colorImages[selectedColor] as List<dynamic>?;
            if (colorImageList != null && colorImageList.isNotEmpty) {
              imageUrl = colorImageList.first as String? ?? imageUrl;
            }
          }

          byId[pid] = {
            'id': pid,
            'image': imageUrl,
            'name': d['productName'] as String? ?? 'Unknown Product',
          };
        }
      }

      if (mounted) {
        setState(() {
          _products = byId.values.toList();
          _loadingProducts = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  Future<void> _loadSellers() async {
    if (!_hasMoreSellers) return;

    setState(() => _loadingSellers = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collectionGroup('reviews')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (_lastSellerDoc != null) {
        q = q.startAfterDocument(_lastSellerDoc!);
      }

      final snap = await q.get();

      if (snap.docs.length < _pageSize) {
        _hasMoreSellers = false;
      }
      if (snap.docs.isNotEmpty) {
        _lastSellerDoc = snap.docs.last;
      }

      final byId = <String, Map<String, dynamic>>{
        for (var s in _sellers) s['id'] as String: s
      };

      for (var doc in snap.docs) {
        final d = doc.data();

        // Check if this is a seller/shop review
        final collectionId = doc.reference.parent.parent?.parent.id;
        if (collectionId == 'users' || collectionId == 'shops') {
          final sellerId = doc.reference.parent.parent!.id;

          if (!byId.containsKey(sellerId)) {
            byId[sellerId] = {
              'id': sellerId,
              'name': d['sellerName'] as String? ?? 'Unknown Seller',
              'type': collectionId == 'shops' ? 'shop' : 'user',
              'image': d['sellerImage'] as String? ?? '',
            };
          }
        }
      }

      if (mounted) {
        setState(() {
          _sellers = byId.values.toList();
          _loadingSellers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sellers: $e');
      if (mounted) {
        setState(() => _loadingSellers = false);
      }
    }
  }

  int _countSelected() {
    int count = 0;
    if (_selectedProductId != null) count++;
    if (_selectedSellerId != null) count++;
    return count;
  }

  Widget _buildCompactProductTile(Map<String, dynamic> product) {
    final imageUrl = product['image'] as String;
    final hasValidImage = _isValidImageUrl(imageUrl);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          // Product Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 50,
              height: 50,
              child: hasValidImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _buildImagePlaceholder(),
                      errorWidget: (_, __, ___) => _buildImagePlaceholder(),
                    )
                  : _buildImagePlaceholder(),
            ),
          ),
          const SizedBox(width: 12),
          // Product Name
          Expanded(
            child: Text(
              product['name'] as String,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSellerTile(Map<String, dynamic> seller) {
    final imageUrl = seller['image'] as String;
    final hasValidImage = _isValidImageUrl(imageUrl);
    final isShop = seller['type'] == 'shop';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          // Seller Image or Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: SizedBox(
              width: 50,
              height: 50,
              child: hasValidImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _buildSellerPlaceholder(isShop),
                      errorWidget: (_, __, ___) =>
                          _buildSellerPlaceholder(isShop),
                    )
                  : _buildSellerPlaceholder(isShop),
            ),
          ),
          const SizedBox(width: 12),
          // Seller Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller['name'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isShop ? 'Shop' : 'Seller',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(
        Icons.image,
        size: 24,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildSellerPlaceholder(bool isShop) {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        isShop ? Icons.store : Icons.person,
        size: 24,
        color: Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.filter),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedProductId = null;
                _selectedSellerId = null;
              });
            },
            child: Text(
              l10n.clear,
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Product Filter
                ExpansionTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.product),
                      if (_selectedProductId != null)
                        const Icon(Icons.check, color: Colors.orange),
                    ],
                  ),
                  trailing: Icon(
                    _isProductExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.orange,
                  ),
                  onExpansionChanged: (expanded) =>
                      setState(() => _isProductExpanded = expanded),
                  children: [
                    if (_products.isEmpty && _loadingProducts)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          controller: _productScrollController,
                          shrinkWrap: true,
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return RadioListTile<String>(
                              value: product['id'] as String,
                              groupValue: _selectedProductId,
                              onChanged: (value) =>
                                  setState(() => _selectedProductId = value),
                              title: _buildCompactProductTile(product),
                              contentPadding: EdgeInsets.zero,
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const Divider(height: 1),

                // Seller Filter
                ExpansionTile(
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.seller),
                      if (_selectedSellerId != null)
                        const Icon(Icons.check, color: Colors.orange),
                    ],
                  ),
                  trailing: Icon(
                    _isSellerExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.orange,
                  ),
                  onExpansionChanged: (expanded) =>
                      setState(() => _isSellerExpanded = expanded),
                  children: [
                    if (_sellers.isEmpty && _loadingSellers)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_sellers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No seller reviews found',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          controller: _sellerScrollController,
                          shrinkWrap: true,
                          itemCount: _sellers.length,
                          itemBuilder: (context, index) {
                            final seller = _sellers[index];
                            return RadioListTile<String>(
                              value: seller['id'] as String,
                              groupValue: _selectedSellerId,
                              onChanged: (value) =>
                                  setState(() => _selectedSellerId = value),
                              title: _buildCompactSellerTile(seller),
                              contentPadding: EdgeInsets.zero,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop({
                    'productId': _selectedProductId,
                    'sellerId': _selectedSellerId,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  '${l10n.apply} (${_countSelected()})',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
