import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/teras_product_list_provider.dart';
import '../../widgets/product_list_sliver.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../widgets/product_card_shimmer.dart'; // ✅ Import ProductCard shimmer

/// Returns multiple slivers: header + product grid
class TerasProductList extends StatefulWidget {
  const TerasProductList({Key? key}) : super(key: key);

  @override
  State<TerasProductList> createState() => _TerasProductListState();
}

class _TerasProductListState extends State<TerasProductList>
    with AutomaticKeepAliveClientMixin {
  late TerasProductListProvider _provider;
  bool _isProviderInitialized = false;
  bool _isInitialLoading = true; // ✅ Track initial loading state

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isProviderInitialized) {
      _provider = Provider.of<TerasProductListProvider>(context, listen: false);

      // ✅ CHECK: Do we have cached data?
      if (_provider.hasCachedData) {
        debugPrint('✅ Using cached Teras data - no loading needed');
        _isInitialLoading = false; // Skip loading indicator
      } else {
        debugPrint('🔄 No cache - initializing Teras provider');
        // ✅ FIX: Defer initialization to avoid calling notifyListeners during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _provider.initialize();
          }
        });
      }

      _isProviderInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer<TerasProductListProvider>(
      builder: (context, provider, _) {
        final combinedProducts = provider.getCombinedProducts();
        final boostedProducts = provider.boostedProducts;
        final regularProducts = combinedProducts
            .where((p) => !p.isBoosted && p.promotionScore <= 1000)
            .toList();

        // Show shimmer until provider has completed initial load
        if (!provider.isInitialized && combinedProducts.isEmpty) {
          return _buildShimmerState(context);
        }

        // Mark first load complete after frame to avoid modifying state during build
        if (_isInitialLoading && combinedProducts.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isInitialLoading) {
              setState(() {
                _isInitialLoading = false;
              });
            }
          });
        }

        // Empty state: only show after provider has initialized and confirmed no products
        if (provider.isInitialized && provider.isEmpty && !provider.isLoadingMore) {
          return _buildEmptyState(context);
        }

        // Return MultiSliver (header + grid)
        return _buildMultiSliver(regularProducts, boostedProducts, provider);
      },
    );
  }

  /// ✅ Build shimmer loading state
  Widget _buildShimmerState(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final portraitImageHeight = screenHeight * 0.30;

    return SliverMainAxisGroup(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple, Colors.pink],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Text(
              AppLocalizations.of(context).latestArrivals,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        // ✅ Shimmer grid - matches ProductListSliver layout
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 8.0,
              mainAxisSpacing: 8.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductCardShimmer(
                portraitImageHeight: portraitImageHeight,
                scaleFactor: 0.88,
              ),
              childCount: 6, // Show 6 shimmer cards
            ),
          ),
        ),
      ],
    );
  }

  /// ✅ Build empty state
  Widget _buildEmptyState(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        height: 300,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noProductsFound,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  /// Build multiple slivers wrapped in SliverMainAxisGroup
  Widget _buildMultiSliver(
    List<dynamic> regularProducts,
    List<dynamic> boostedProducts,
    TerasProductListProvider provider,
  ) {
    return SliverMainAxisGroup(
      slivers: [
        // Header sliver
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple, Colors.pink],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Text(
              AppLocalizations.of(context).latestArrivals,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Product grid sliver
        ProductListSliver(
          products: regularProducts as List<Product>,
          boostedProducts: boostedProducts as List<Product>,
          hasMore: provider.hasMore,
          screenName: 'teras_product_list',
          isLoadingMore: provider.isLoadingMore,
        ),
      ],
    );
  }
}