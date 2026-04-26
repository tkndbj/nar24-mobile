import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/market_provider.dart';
import '../../providers/dynamic_market_provider.dart';
import '../DYNAMIC-SCREENS/dynamic_market.dart';
import '../../widgets/product_card.dart';
import '../../models/product_summary.dart';
import '../../models/category_structure.dart';
import '../../route_observer.dart';
import '../../services/typesense_service_manager.dart';
import '../../widgets/product_card_shimmer.dart';
import '../../services/category_cache_service.dart';

/// Maps buyer category keys to their sidebar icons.
/// Centralized here so adding/changing icons doesn't require touching widget code.
const Map<String, IconData> _kBuyerCategoryIcons = {
  'Women': FeatherIcons.user,
  'Men': FeatherIcons.user,
  'Mother & Child': FeatherIcons.heart,
  'Home & Furniture': FeatherIcons.home,
  'Electronics': FeatherIcons.smartphone,
  'Books, Stationery & Hobby': FeatherIcons.book,
  'Flowers & Gifts': FeatherIcons.gift,
  'Sports & Outdoor': FeatherIcons.activity,
  'Tools & Hardware': FeatherIcons.settings,
  'Pet Supplies': FeatherIcons.heart,
  'Automotive': FeatherIcons.truck,
  'Health & Wellness': FeatherIcons.heart,
};

const double _kSidebarWidth = 100.0;
const double _kSidebarItemHeight = 80.0;
const Color _kDividerColor = Color.fromARGB(255, 230, 230, 230);

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({Key? key}) : super(key: key);

  @override
  _CategoriesScreenState createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with RouteAware {
  String? _selectedBuyerCategory;
  final ScrollController _scrollController = ScrollController();
  List<ProductSummary> _displayProducts = [];
  final Set<String> _expandedSubcategories = {};
  bool _isLoadingProducts = false;

  /// Monotonic token for product fetches. Each new fetch increments this and
  /// captures the value; when the fetch returns, we only apply results if the
  /// token still matches. Prevents stale responses from clobbering newer ones
  /// when the user taps categories quickly.
  int _fetchToken = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<CategoryCacheService>().initialize();
      if (!mounted) return;
      _initializeBuyerCategory();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Returning to this screen — collapse any open subcategories for a clean
    // state. Do NOT re-fetch products: the data we have is still valid.
    if (!mounted) return;
    setState(() {
      _expandedSubcategories.clear();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    routeObserver.unsubscribe(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  /// Picks the initial buyer category. Prefers 'Women' if present (legacy
  /// default), otherwise falls back to the first available category. This
  /// guards against the structure not containing 'Women' for any reason.
  void _initializeBuyerCategory() {
    final structure = context.read<CategoryCacheService>().structure;
    if (structure == null || structure.buyerCategories.isEmpty) return;

    const preferredDefault = 'Women';
    final hasPreferred =
        structure.buyerCategories.any((c) => c.key == preferredDefault);
    final initial =
        hasPreferred ? preferredDefault : structure.buyerCategories.first.key;

    setState(() {
      _selectedBuyerCategory = initial;
    });

    _fetchProductsForBuyerCategory(initial);
    _scrollToSelectedCategory();
  }

  void _scrollToSelectedCategory() {
    if (!mounted || !_scrollController.hasClients) return;

    final structure = context.read<CategoryCacheService>().structure;
    if (structure == null || _selectedBuyerCategory == null) return;

    final catIndex = structure.buyerCategories
        .indexWhere((c) => c.key == _selectedBuyerCategory);
    if (catIndex == -1) return;

    final offset = catIndex * _kSidebarItemHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _fetchProductsForBuyerCategory(String buyerCategory) async {
    final myToken = ++_fetchToken;

    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final marketProvider = context.read<MarketProvider>();
      final products =
          await marketProvider.fetchProductsForBuyerCategory(buyerCategory);

      // Discard if a newer fetch was started or widget is gone.
      if (!mounted || myToken != _fetchToken) return;

      final validProducts = _filterValidProducts(products);
      setState(() {
        _displayProducts = validProducts;
        _isLoadingProducts = false;
      });
    } catch (e, st) {
      debugPrint('Error fetching products for $buyerCategory: $e\n$st');
      if (!mounted || myToken != _fetchToken) return;
      setState(() {
        _displayProducts = [];
        _isLoadingProducts = false;
      });
    }
  }

  List<ProductSummary> _filterValidProducts(List<ProductSummary> products) {
    return products.where((p) {
      return p.productName.isNotEmpty &&
          ((p.brandModel?.isNotEmpty ?? false) || (p.quantity > 0));
    }).toList();
  }

  IconData _iconForBuyerCategory(String key) =>
      _kBuyerCategoryIcons[key] ?? FeatherIcons.grid;

  Future<void> _onBuyerCategoryTap(String key) async {
    if (_selectedBuyerCategory == key) return;

    setState(() {
      _selectedBuyerCategory = key;
      _expandedSubcategories.clear();
      _displayProducts = [];
    });

    await _fetchProductsForBuyerCategory(key);
  }

  void _navigateToProductScreen({
    required CategoryStructure structure,
    required String buyerCategory,
    required BuyerSubcategory sub,
    required BuyerSubSubcategory subSub,
    required String langCode,
  }) {
    if (!mounted) return;

    final mapping = structure.getBuyerToProductMapping(
      buyerCategory,
      sub.key,
      subSub.key,
    );
    final displayName = subSub.getLabel(langCode);
    final isFashion = buyerCategory == 'Women' || buyerCategory == 'Men';

    final screen = DynamicMarketScreen(
      category: mapping['category'] ?? buyerCategory,
      selectedSubcategory: isFashion
          ? mapping['subcategory']
          : (mapping['subcategory'] ?? sub.key),
      selectedSubSubcategory: isFashion
          ? mapping['subSubcategory']
          : (mapping['subSubcategory'] ?? subSub.key),
      displayName: displayName,
      buyerCategory: buyerCategory,
      buyerSubcategory: sub.key,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<ShopMarketProvider>(
          create: (_) => ShopMarketProvider(
            searchService: TypeSenseServiceManager.instance.shopService,
          ),
          child: screen,
        ),
      ),
    ).catchError((error) {
      debugPrint('Navigation error: $error');
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Localizations.localeOf(context).languageCode;

    // watch — so if the cache service notifies (e.g. async load completes
    // after this build, or a future refresh is added), we rebuild.
    final structure = context.watch<CategoryCacheService>().structure;

    if (structure == null || _selectedBuyerCategory == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final buyerCategories = structure.buyerCategories;
    final buyerSubcategories =
        structure.getSubcategories(_selectedBuyerCategory!);

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Sidebar(
            scrollController: _scrollController,
            categories: buyerCategories,
            selectedKey: _selectedBuyerCategory!,
            langCode: langCode,
            iconResolver: _iconForBuyerCategory,
            onTap: _onBuyerCategoryTap,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._buildSubcategoryTiles(
                    structure: structure,
                    subcategories: buyerSubcategories,
                    langCode: langCode,
                  ),
                  if (_isLoadingProducts)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: _ResponsiveProductGrid.shimmer(),
                    )
                  else if (_displayProducts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ResponsiveProductGrid.products(
                        products: _displayProducts,
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSubcategoryTiles({
    required CategoryStructure structure,
    required List<BuyerSubcategory> subcategories,
    required String langCode,
  }) {
    final tiles = <Widget>[];
    for (var idx = 0; idx < subcategories.length; idx++) {
      final sub = subcategories[idx];
      final subSubcategories = structure.getSubSubcategories(
        _selectedBuyerCategory!,
        sub.key,
      );
      final isExpanded = _expandedSubcategories.contains(sub.key);

      tiles.add(ExpansionTile(
        key: ValueKey('${_selectedBuyerCategory}_${sub.key}'),
        title: Text(
          sub.getLabel(langCode),
          style: TextStyle(
            fontSize: 14,
            color: isExpanded
                ? Colors.orange
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        tilePadding: const EdgeInsets.only(left: 8),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        onExpansionChanged: (expanded) {
          // Pure UI state change. No network calls — products are tied to the
          // buyer category, not subcategory expansion.
          setState(() {
            if (expanded) {
              _expandedSubcategories.add(sub.key);
            } else {
              _expandedSubcategories.remove(sub.key);
            }
          });
        },
        children: [
          for (var subIdx = 0; subIdx < subSubcategories.length; subIdx++) ...[
            ListTile(
              contentPadding: const EdgeInsets.only(left: 32),
              title: Text(
                subSubcategories[subIdx].getLabel(langCode),
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              onTap: () => _navigateToProductScreen(
                structure: structure,
                buyerCategory: _selectedBuyerCategory!,
                sub: sub,
                subSub: subSubcategories[subIdx],
                langCode: langCode,
              ),
            ),
            if (subIdx < subSubcategories.length - 1)
              const Divider(
                height: 1,
                thickness: 0.5,
                color: _kDividerColor,
              ),
          ],
        ],
      ));

      if (idx < subcategories.length - 1) {
        tiles.add(const Divider(
          height: 1,
          thickness: 1,
          color: _kDividerColor,
        ));
      }
    }
    return tiles;
  }
}

// ─── Sidebar ───────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final ScrollController scrollController;
  final List<BuyerCategory> categories;
  final String selectedKey;
  final String langCode;
  final IconData Function(String) iconResolver;
  final Future<void> Function(String) onTap;

  const _Sidebar({
    required this.scrollController,
    required this.categories,
    required this.selectedKey,
    required this.langCode,
    required this.iconResolver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: _kSidebarWidth,
      color: isLight ? Colors.grey[50] : const Color.fromARGB(255, 33, 31, 49),
      child: ListView.builder(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: categories.length,
        itemBuilder: (ctx, i) {
          final cat = categories[i];
          final isSelected = cat.key == selectedKey;

          return SizedBox(
            height: _kSidebarItemHeight,
            child: Material(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : Colors.transparent,
              child: InkWell(
                onTap: () => onTap(cat.key),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconResolver(cat.key),
                        color: isSelected ? Colors.orange : Colors.grey[500],
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cat.getLabel(langCode),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.orange
                              : isLight
                                  ? Colors.grey[600]
                                  : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Responsive product grid ───────────────────────────────────────────────
//
// Single widget that handles both shimmer and real product rendering. Layout
// rules (breakpoints, spacing, image heights, aspect ratios) live in ONE place
// so shimmer and product grid can never drift out of sync.

class _ResponsiveProductGrid extends StatelessWidget {
  final List<ProductSummary>? products;
  final bool isShimmer;

  const _ResponsiveProductGrid.shimmer()
      : products = null,
        isShimmer = true;

  const _ResponsiveProductGrid.products({required this.products})
      : isShimmer = false;

  static const int _shimmerCount = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 600;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final isTabletPortrait = isTablet && !isLandscape;

        final crossAxisSpacing = isTablet ? 6.0 : 8.0;
        final mainAxisSpacing =
            isTabletPortrait ? 16.0 : (isTablet ? 6.0 : 18.0);
        final imageHeight =
            isTabletPortrait ? 262.0 : (isTablet ? 132.0 : 155.0);

        final itemCount = isShimmer ? _shimmerCount : (products?.length ?? 0);

        if (isTabletPortrait) {
          final availableWidth =
              constraints.maxWidth - 16 - (3 * crossAxisSpacing);
          final itemWidth = availableWidth / 4;
          final itemHeight = imageHeight + 95;

          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: itemWidth + 1,
              mainAxisExtent: itemHeight,
              mainAxisSpacing: mainAxisSpacing,
              crossAxisSpacing: crossAxisSpacing,
            ),
            itemBuilder: (ctx, i) => _buildItem(
              i,
              imageHeight: imageHeight,
              scaleFactor: 0.9,
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isTablet ? 5 : 2,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: isTablet ? 0.50 : 0.46,
          ),
          itemBuilder: (ctx, i) => _buildItem(
            i,
            imageHeight: imageHeight,
            scaleFactor: isTablet ? 0.9 : 1.0,
          ),
        );
      },
    );
  }

  Widget _buildItem(
    int index, {
    required double imageHeight,
    required double scaleFactor,
  }) {
    if (isShimmer) {
      return ProductCardShimmer(
        portraitImageHeight: imageHeight,
        scaleFactor: scaleFactor,
      );
    }
    final product = products![index];
    return ProductCard(
      key: ValueKey(product.id),
      product: product,
      scaleFactor: scaleFactor,
      internalScaleFactor: 1.0,
      portraitImageHeight: imageHeight,
    );
  }
}
