import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../providers/product_detail_provider.dart';
import '../../providers/product_repository.dart';
import '../../screens/PRODUCT-SCREENS/product_detail_screen.dart';
import 'package:shimmer/shimmer.dart';

class ProductCollectionWidget extends StatefulWidget {
  final String productId;
  final String? shopId;

  const ProductCollectionWidget({
    Key? key,
    required this.productId,
    this.shopId,
  }) : super(key: key);

  @override
  State<ProductCollectionWidget> createState() =>
      _ProductCollectionWidgetState();
}

class _ProductCollectionWidgetState extends State<ProductCollectionWidget>
    with AutomaticKeepAliveClientMixin {
  late final Future<CollectionData?> _collectionFuture;

  @override
  void initState() {
    super.initState();
    _collectionFuture = _fetchProductCollection();
  }

  @override
  bool get wantKeepAlive => true;

  Future<CollectionData?> _fetchProductCollection() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Only proceed if we have a shopId
      if (widget.shopId == null || widget.shopId!.isEmpty) {
        return null;
      }

      // Find collection that contains this product
      final collectionsSnapshot = await firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('collections')
          .where('productIds', arrayContains: widget.productId)
          .limit(1)
          .get();

      if (collectionsSnapshot.docs.isEmpty) {
        return null;
      }

      final collectionDoc = collectionsSnapshot.docs.first;
      final collectionData = collectionDoc.data();
      final productIds = List<String>.from(collectionData['productIds'] ?? []);

      // Remove current product from the list
      productIds.remove(widget.productId);

      if (productIds.isEmpty) {
        return null;
      }

      // Fetch products from the collection (max 10)
      final products = <Product>[];
      final limitedProductIds = productIds.take(10).toList();

      // Fetch products in batches to avoid Firestore limit
      for (int i = 0; i < limitedProductIds.length; i += 10) {
        final batch = limitedProductIds.skip(i).take(10).toList();

        final productsSnapshot = await firestore
            .collection('shop_products')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in productsSnapshot.docs) {
          try {
            // **FIXED**: Use fromDocument to properly include the document ID
            final product = Product.fromDocument(doc);

            // **VALIDATION**: Check if product ID is valid
            if (product.id.trim().isEmpty) {
              debugPrint(
                  'Warning: Product with empty ID found in document: ${doc.id}');
              continue; // Skip this product
            }

            products.add(product);
          } catch (e) {
            debugPrint('Error parsing product ${doc.id}: $e');
          }
        }
      }

      if (products.isEmpty) {
        return null;
      }

      return CollectionData(
        id: collectionDoc.id,
        name: collectionData['name'] ?? 'Collection',
        imageUrl: collectionData['imageUrl'],
        products: products,
      );
    } catch (e) {
      debugPrint('Error fetching product collection: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<CollectionData?>(
      future: _collectionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState(isDark);
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final collectionData = snapshot.data!;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(collectionData, l10n, isDark),
              const SizedBox(height: 12),
              _buildProductsList(collectionData.products, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(bool isDark) {
    final baseColor = isDark ? const Color(0xFF1C1A29) : Colors.grey[300]!;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 51, 48, 73) : Colors.grey[100]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    width: 150,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 80,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                itemBuilder: (_, idx) => Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      CollectionData collectionData, AppLocalizations l10n, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.seeFromThisCollection,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            _navigateToCollection(collectionData);
          },
          child: Text(
            l10n.viewAll,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsList(List<Product> products, bool isDark) {
    return SizedBox(
      height: 80, // Reduced from 120 to 80
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index < products.length - 1 ? 16 : 0,
            ),
            child: _CollectionProductCard(product: product),
          );
        },
      ),
    );
  }

  void _navigateToCollection(CollectionData collectionData) {
    try {
      // Navigate to dynamic collection screen
      context.push('/collection/${collectionData.id}', extra: {
        'shopId': widget.shopId,
        'collectionName': collectionData.name,
      });
    } catch (e) {
      debugPrint('Error navigating to collection: $e');
    }
  }
}

class _CollectionProductCard extends StatelessWidget {
  final Product product;

  const _CollectionProductCard({
    Key? key,
    required this.product,
  }) : super(key: key);

  String formatPrice(num price) {
    double rounded = double.parse(price.toStringAsFixed(2));

    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }

    return rounded.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        _navigateToProduct(context);
      },
      child: Container(
        width: 200,
        height: 80, // Keep image height
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Product image - fully covers the left side with left-only rounded corners
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(
                    7), // Slightly less than container to account for border
                bottomLeft: Radius.circular(7),
              ),
              child: Container(
                width: 80,
                height: 80,
                child: product.imageUrls.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.imageUrls.first,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                          child: Icon(
                            Icons.image,
                            color:
                                isDark ? Colors.white30 : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                          child: Icon(
                            Icons.image_not_supported,
                            color:
                                isDark ? Colors.white30 : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.image,
                          color: isDark ? Colors.white30 : Colors.grey.shade400,
                          size: 20,
                        ),
                      ),
              ),
            ),

            // Product details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Product name - allows 2 lines with ellipsis
                    Text(
                      product.productName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Price
                    Text(
                      '${formatPrice(product.price)} ${product.currency}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
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

  void _navigateToProduct(BuildContext context) {
    try {
      // **VALIDATION**: Check if product ID is valid before navigation
      if (product.id.trim().isEmpty) {
        debugPrint('Error: Cannot navigate to product with empty ID');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product not available')),
        );
        return;
      }

      // **FIXED**: Use proper navigation with provider setup like ProductCard does
      final repo = context.read<ProductRepository>();

      final route = PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) =>
            ChangeNotifierProvider(
          create: (_) => ProductDetailProvider(
            productId: product.id,
            repository: repo,
            initialProduct: product,
          ),
          child: ProductDetailScreen(productId: product.id),
        ),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          final tween = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      );

      Navigator.of(context).push(route);
    } catch (e) {
      debugPrint('Error navigating to product: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Navigation error: $e')),
      );
    }
  }
}

class CollectionData {
  final String id;
  final String name;
  final String? imageUrl;
  final List<Product> products;

  CollectionData({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.products,
  });
}
