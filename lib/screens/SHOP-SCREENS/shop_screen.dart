// lib/screens/SHOP-SCREENS/shop_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/shop_provider.dart';
import '../../widgets/shop/shop_card_widget.dart';
import 'create_shop_screen.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/shop/shop_search_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// A helper widget to draw gradient text.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;

  const GradientText({
    Key? key,
    required this.text,
    required this.style,
    required this.gradient,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: style,
      ),
    );
  }
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({Key? key}) : super(key: key);

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _isInitialized = false;
  List<DocumentSnapshot>? _searchResults;
  bool _isSearchLoading = false;
  final GlobalKey<ShopSearchBarState> _searchBarKey =
      GlobalKey<ShopSearchBarState>(); // ✅ Fixed

  @override
  void initState() {
    super.initState();
    // Use WidgetsBinding to ensure the widget is built before accessing context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeShops();
    });
  }

  Future<void> _initializeShops() async {
    if (_isInitialized || !mounted) return;

    final shopProvider = context.read<ShopProvider>();

    // Ensure we have a clean state
    await shopProvider.ensureInitialized();

    // Only call setState if the widget is still mounted
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onSearchResultsChanged(
      List<DocumentSnapshot>? results, bool isLoading) {
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearchLoading = isLoading;
    });
  }

  Future<void> _onSearchCleared() async {
    if (!mounted) return;

    // Clear search state
    setState(() {
      _searchResults = null;
      _isSearchLoading = false;
    });

    // Tell provider to reset and refetch all shops
    final shopProvider = context.read<ShopProvider>();
    await shopProvider.clearShopSearch();
  }

  int _calculateCrossAxisCount(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;

    // Determine if it's a tablet/larger screen
    final isTablet = screenWidth >= 600;

    if (!isTablet) {
      return 2; // Mobile: always 2 columns
    }

    // Tablet responsive columns
    if (orientation == Orientation.portrait) {
      return screenWidth >= 900 ? 4 : 3; // Portrait: 3-4 columns
    } else {
      return screenWidth >= 1200 ? 6 : 5; // Landscape: 5-6 columns
    }
  }

  double _calculateAspectRatio(BuildContext context) {
    // Only used for mobile - tablets use mainAxisExtent instead
    return 0.9;
  }

  double? _calculateMainAxisExtent(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    if (!isTablet) {
      return null; // Mobile uses childAspectRatio
    }

    // Tablet: fixed height for precise control
    // Cover image (120) + padding (8*2) + top spacing (8) + shop name (~40) + rating (~16) = ~200
    return 200.0;
  }

  SliverGridDelegate _buildGridDelegate(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final crossAxisCount = _calculateCrossAxisCount(context);

    if (isTablet) {
      // Tablet: use mainAxisExtent for precise height control
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 2.0,
        mainAxisSpacing: 2.0,
        mainAxisExtent: _calculateMainAxisExtent(context),
      );
    } else {
      // Mobile: use childAspectRatio
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 2.0,
        mainAxisSpacing: 2.0,
        childAspectRatio: _calculateAspectRatio(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userOwnsShop = context.watch<ShopProvider>().userOwnsShop;
    final l10n = AppLocalizations.of(context);
    final shopProvider = context.read<ShopProvider>();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      // Dismiss keyboard when tapping outside
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Text(
            l10n.shops,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          elevation: 0,
          actions: [
            if (userOwnsShop)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: GestureDetector(
                  onTap: () {
                    final String? userId =
                        FirebaseAuth.instance.currentUser?.uid;
                    if (userId != null) {
                      context.push('/seller-panel');
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.purple, Colors.pink],
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: GradientText(
                          text: l10n.panel,
                          gradient: const LinearGradient(
                            colors: [Colors.purple, Colors.pink],
                          ),
                          style: const TextStyle(fontSize: 12.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Search Bar - Always visible under AppBar
              ShopSearchBar(
                key: _searchBarKey,
                onSearchResultsChanged: _onSearchResultsChanged,
                onSearchCleared: _onSearchCleared,
              ),

              // Main Content
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    // ✅ Clear search state first
                    if (mounted) {
                      setState(() {
                        _searchResults = null;
                        _isSearchLoading = false;
                      });
                    }

                    // ✅ Clear search in search bar
                    _searchBarKey.currentState?.clearSearchAndUnfocus();

                    // ✅ Refresh shops (now properly clears and refetches)
                    await shopProvider.refreshShops();
                  },
                  child: CustomScrollView(
                    controller: shopProvider.scrollController,
                    slivers: [
                      // Create Shop Button
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const CreateShopScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00A86B),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(0),
                              ),
                              elevation: 0,
                            ),
                            child: Text(l10n.createYourShop),
                          ),
                        ),
                      ),

                      // Shops Grid
                      _buildShopsSliver(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopsSliver(BuildContext context) {
    final shopProvider = Provider.of<ShopProvider>(context);
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58)
        : Colors.grey.shade300;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78)
        : Colors.grey.shade100;

    // Show search loading shimmer
    if (_isSearchLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        sliver: SliverGrid(
          gridDelegate: _buildGridDelegate(context),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(baseColor, highlightColor),
            childCount: 6,
          ),
        ),
      );
    }

    // Show search results if available
    if (_searchResults != null) {
      if (_searchResults!.isEmpty) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 48,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noResultsFound ?? 'No shops found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        );
      }

      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        sliver: SliverGrid(
          gridDelegate: _buildGridDelegate(context),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final doc = _searchResults![index];
              final shopData = doc.data() as Map<String, dynamic>;
              final shopId = doc.id;
              final avgRating = shopProvider.averageRatings[shopId] ?? 0.0;

              return ShopCardWidget(
                shop: shopData,
                shopId: shopId,
                averageRating: avgRating,
              );
            },
            childCount: _searchResults!.length,
          ),
        ),
      );
    }

    // Handle error state from provider
    if (shopProvider.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.errorLoadingShops ?? 'Error loading shops',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => shopProvider.retryLoading(),
                child: Text(l10n.retry ?? 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Initial loading with shimmer
    if (shopProvider.isInitialLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
        sliver: SliverGrid(
          gridDelegate: _buildGridDelegate(context),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(baseColor, highlightColor),
            childCount: 6,
          ),
        ),
      );
    }

    // No shops available
    if (shopProvider.shops.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.store_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.noShopsAvailable,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    // Default shops list (all shops from provider)
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      sliver: SliverGrid(
        gridDelegate: _buildGridDelegate(context),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Load more indicator
            if (index == shopProvider.shops.length) {
              if (shopProvider.hasMore && shopProvider.isLoadingMore) {
                return _buildShimmerCard(baseColor, highlightColor);
              }
              return const SizedBox.shrink();
            }

            // Regular shop card
            final doc = shopProvider.shops[index];
            final shopData = doc.data() as Map<String, dynamic>;
            final shopId = doc.id;
            final avgRating = shopProvider.averageRatings[shopId] ?? 0.0;

            return ShopCardWidget(
              shop: shopData,
              shopId: shopId,
              averageRating: avgRating,
            );
          },
          childCount: shopProvider.shops.length +
              (shopProvider.hasMore && shopProvider.isLoadingMore ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildShimmerCard(Color baseColor, Color highlightColor) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        margin: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
