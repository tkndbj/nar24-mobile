import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';

class DynamicQuestionsFilterScreen extends StatefulWidget {
  final String sellerId;
  final bool isShopProduct;
  final String? initialProductId;

  const DynamicQuestionsFilterScreen({
    Key? key,
    required this.sellerId,
    required this.isShopProduct,
    this.initialProductId,
  }) : super(key: key);

  @override
  _DynamicQuestionsFilterScreenState createState() =>
      _DynamicQuestionsFilterScreenState();
}

class _DynamicQuestionsFilterScreenState
    extends State<DynamicQuestionsFilterScreen> {
  bool _isProductExpanded = false;
  late ScrollController _productScrollController;
  String? _selectedProductId;

  static const int _pageSize = 20;
  DocumentSnapshot<Map<String, dynamic>>? _lastQuestionDoc;
  bool _hasMoreQuestions = true;

  List<Map<String, dynamic>> _products = [];
  bool _loadingProducts = true;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    _productScrollController = ScrollController();
    _productScrollController.addListener(_onProductScroll);
    _loadProducts();
  }

  @override
  void dispose() {
    _productScrollController.dispose();
    super.dispose();
  }

  void _onProductScroll() {
    final pos = _productScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_loadingProducts &&
        _hasMoreQuestions) {
      _loadProducts();
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
    if (!_hasMoreQuestions) return;
    setState(() => _loadingProducts = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collectionGroup('product_questions')
          .where('sellerId', isEqualTo: widget.sellerId)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize);

      if (_lastQuestionDoc != null) {
        q = q.startAfterDocument(_lastQuestionDoc!);
      }

      final snap = await q.get();

      if (snap.docs.length < _pageSize) {
        _hasMoreQuestions = false;
      }
      if (snap.docs.isNotEmpty) {
        _lastQuestionDoc = snap.docs.last;
      }

      final Map<String, Map<String, dynamic>> byId = {
        for (var p in _products) p['id'] as String: p
      };

      for (var doc in snap.docs) {
        final d = doc.data();
        final pid = d['productId'] as String?;
        
        // Skip if productId is null or empty
        if (pid == null || pid.trim().isEmpty) continue;

        if (!byId.containsKey(pid)) {
          byId[pid] = {
            'id': pid,
            'image': d['productImage'] as String? ?? '',
            'name': d['productName'] as String? ?? 'Unknown Product',
            'price': (d['productPrice'] as num?)?.toDouble() ?? 0.0,
            'rating': (d['productRating'] as num?)?.toDouble() ?? 0.0,
            'currency': d['currency'] as String? ?? '',
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

  int _countSelected() {
    return _selectedProductId != null ? 1 : 0;
  }

  Widget _buildCompactProductTile(Map<String, dynamic> product) {
    final imageUrl = product['image'] as String? ?? '';
    final hasValidImage = _isValidImageUrl(imageUrl);
    final productName = product['name'] as String? ?? 'Unknown Product';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final rating = (product['rating'] as num?)?.toDouble() ?? 0.0;
    final currency = product['currency'] as String? ?? '';

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
          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (price > 0) ...[
                      Text(
                        '${price.toStringAsFixed(2)} ${currency}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (rating > 0) ...[
                      Icon(
                        Icons.star,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
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
                    else if (_products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No products found',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
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