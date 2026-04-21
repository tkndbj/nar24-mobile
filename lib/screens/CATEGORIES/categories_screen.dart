import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:provider/provider.dart';
// ✅ AllInOneCategoryData no longer needed for localization — REMOVED
import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_provider.dart';
import '../../providers/dynamic_market_provider.dart';
import '../DYNAMIC-SCREENS/dynamic_market.dart';
import '../../widgets/product_card.dart';
import '../../models/product_summary.dart';
import '../../route_observer.dart';
import '../../services/typesense_service_manager.dart';
import '../../widgets/product_card_shimmer.dart';
import '../../models/category_structure.dart';
import '../../services/category_cache_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({Key? key}) : super(key: key);

  @override
  _CategoriesScreenState createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with RouteAware {
  String _selectedBuyerCategory = 'Women';
  String? _selectedBuyerSubcategory;
  final ScrollController _scrollController = ScrollController();
  List<ProductSummary> _displayProducts = [];
  Set<String> _expandedSubcategories = {};
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<CategoryCacheService>(context, listen: false)
          .initialize();
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
    setState(() {
      _expandedSubcategories.clear();
    });
    _fetchProductsForBuyerCategory(_selectedBuyerCategory);
  }

  Future<void> _initializeBuyerCategory() async {
    await _fetchProductsForBuyerCategory(_selectedBuyerCategory);
    _scrollToSelectedCategory();
  }

  void _scrollToSelectedCategory() {
    if (!mounted || !_scrollController.hasClients) return;

    final structure =
        Provider.of<CategoryCacheService>(context, listen: false).structure;
    if (structure == null) return;

    final buyerCategories =
        structure.kBuyerCategories.map((c) => c['key']!).toList();
    final catIndex =
        buyerCategories.indexWhere((c) => c == _selectedBuyerCategory);

    if (catIndex != -1) {
      final offset = catIndex * 80.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            offset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  Future<void> _fetchProductsForBuyerCategory(String buyerCategory) async {
    if (_isLoadingProducts) return;

    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final marketProvider =
          Provider.of<MarketProvider>(context, listen: false);
      final products =
          await marketProvider.fetchProductsForBuyerCategory(buyerCategory);

      if (!mounted) return;

      final validProducts = _filterValidProducts(products);
      setState(() {
        _displayProducts = validProducts;
      });
    } catch (e, st) {
      debugPrint('Error fetching products for $buyerCategory: $e\n$st');
      if (mounted) {
        setState(() {
          _displayProducts = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  List<ProductSummary> _filterValidProducts(List<ProductSummary> products) {
    return products.where((p) {
      return p.productName.isNotEmpty &&
          ((p.brandModel?.isNotEmpty ?? false) || (p.quantity > 0));
    }).toList();
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

  IconData _getIconForBuyerCategory(String key) {
    switch (key) {
      case 'Women':
        return FeatherIcons.user;
      case 'Men':
        return FeatherIcons.user;
      case 'Mother & Child':
        return FeatherIcons.heart;
      case 'Home & Furniture':
        return FeatherIcons.home;
      case 'Electronics':
        return FeatherIcons.smartphone;
      case 'Books, Stationery & Hobby':
        return FeatherIcons.book;
      case 'Flowers & Gifts':
        return FeatherIcons.gift;
      case 'Sports & Outdoor':
        return FeatherIcons.activity;
      case 'Tools & Hardware':
        return FeatherIcons.settings;
      case 'Pet Supplies':
        return FeatherIcons.heart;
      case 'Automotive':
        return FeatherIcons.truck;
      case 'Health & Wellness':
        return FeatherIcons.heart;
      default:
        return FeatherIcons.grid;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Get current language code for label resolution
    final String langCode = Localizations.localeOf(context).languageCode;

    final structure =
        Provider.of<CategoryCacheService>(context, listen: false).structure;

    if (structure == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ✅ Now returns List<BuyerCategory> — has .getLabel()
    final buyerCategories = structure.buyerCategories;

    // ✅ Now returns List<BuyerSubcategory> — has .getLabel()
    final buyerSubcategories =
        structure.getSubcategories(_selectedBuyerCategory);

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sidebar ──────────────────────────────────────────────────────
          Container(
            width: 100.0,
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.grey[50]
                : const Color.fromARGB(255, 33, 31, 49),
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: buyerCategories.length,
              itemBuilder: (ctx, i) {
                final cat = buyerCategories[i];
                final isSelected = cat.key == _selectedBuyerCategory;

                return SizedBox(
                  height: 80.0,
                  child: Material(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        if (_selectedBuyerCategory == cat.key) return;

                        setState(() {
                          _selectedBuyerCategory = cat.key;
                          _selectedBuyerSubcategory = null;
                          _expandedSubcategories.clear();
                          _displayProducts = [];
                        });

                        if (_displayProducts.isEmpty) {
                          await _fetchProductsForBuyerCategory(cat.key);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getIconForBuyerCategory(cat.key),
                              color:
                                  isSelected ? Colors.orange : Colors.grey[500],
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              // ✅ CHANGE: was AllInOneCategoryData.localizeBuyerCategoryKey(cat.key, l10n)
                              cat.getLabel(langCode),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.orange
                                    : Theme.of(context).brightness ==
                                            Brightness.light
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
          ),

          // ── Main content ─────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...buyerSubcategories.asMap().entries.map((e) {
                    final idx = e.key;
                    final sub = e.value; // BuyerSubcategory object

                    // ✅ CHANGE: was AllInOneCategoryData.kBuyerSubSubcategories[...][...]
                    // Now returns List<BuyerSubSubcategory>
                    final subSubcategories = structure.getSubSubcategories(
                      _selectedBuyerCategory,
                      sub.key,
                    );

                    return Column(
                      children: [
                        ExpansionTile(
                          key: ValueKey(
                              '${_selectedBuyerCategory}_${sub.key}'),
                          title: Text(
                            // ✅ CHANGE: was AllInOneCategoryData.localizeBuyerSubcategoryKey(...)
                            sub.getLabel(langCode),
                            style: TextStyle(
                              fontSize: 14,
                              color: _expandedSubcategories.contains(sub.key)
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          tilePadding: const EdgeInsets.only(left: 8),
                          shape: const RoundedRectangleBorder(),
                          collapsedShape: const RoundedRectangleBorder(),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedSubcategories.add(sub.key);
                              } else {
                                _expandedSubcategories.remove(sub.key);
                                _displayProducts = [];
                                _fetchProductsForBuyerCategory(
                                    _selectedBuyerCategory);
                              }
                            });
                          },
                          children: subSubcategories.asMap().entries.map((subSubEntry) {
                            final subSubIdx = subSubEntry.key;
                            final subSub = subSubEntry.value; // BuyerSubSubcategory

                            return Column(
                              children: [
                                ListTile(
                                  contentPadding:
                                      const EdgeInsets.only(left: 32),
                                  title: Text(
                                    // ✅ CHANGE: was AllInOneCategoryData.localizeBuyerSubSubcategoryKey(...)
                                    subSub.getLabel(langCode),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  onTap: () {
                                    if (!mounted) return;

                                    final mapping =
                                        structure.getBuyerToProductMapping(
                                      _selectedBuyerCategory,
                                      sub.key,
                                      subSub.key,
                                    );

                                    // ✅ displayName now uses label too
                                    final displayName = subSub.getLabel(langCode);

                                    final screen = (_selectedBuyerCategory ==
                                                'Women' ||
                                            _selectedBuyerCategory == 'Men')
                                        ? DynamicMarketScreen(
                                            category: mapping['category'] ??
                                                _selectedBuyerCategory,
                                            selectedSubcategory:
                                                mapping['subcategory'],
                                            selectedSubSubcategory:
                                                mapping['subSubcategory'],
                                            displayName: displayName,
                                            buyerCategory:
                                                _selectedBuyerCategory,
                                            buyerSubcategory: sub.key,
                                          )
                                        : DynamicMarketScreen(
                                            category: mapping['category'] ??
                                                _selectedBuyerCategory,
                                            selectedSubcategory:
                                                mapping['subcategory'] ??
                                                    sub.key,
                                            selectedSubSubcategory:
                                                mapping['subSubcategory'] ??
                                                    subSub.key,
                                            displayName: displayName,
                                            buyerCategory:
                                                _selectedBuyerCategory,
                                            buyerSubcategory: sub.key,
                                          );

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChangeNotifierProvider<
                                            ShopMarketProvider>(
                                          create: (_) => ShopMarketProvider(
                                            searchService:
                                                TypeSenseServiceManager
                                                    .instance.shopService,
                                          ),
                                          child: screen,
                                        ),
                                      ),
                                    ).catchError((error) {
                                      debugPrint('Navigation error: $error');
                                      return null;
                                    });
                                  },
                                ),
                                if (subSubIdx < subSubcategories.length - 1)
                                  const Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: Color.fromARGB(255, 230, 230, 230),
                                  ),
                              ],
                            );
                          }).toList(),
                        ),
                        if (idx < buyerSubcategories.length - 1)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color.fromARGB(255, 230, 230, 230),
                          ),
                      ],
                    );
                  }).toList(),

                  // ── Shimmer and product grid — completely unchanged ───────

                  if (_isLoadingProducts)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isTablet = constraints.maxWidth >= 600;
                          final bool isLandscape =
                              MediaQuery.of(context).orientation ==
                                  Orientation.landscape;
                          final bool isTabletPortrait =
                              isTablet && !isLandscape;
                          final double crossAxisSpacing = isTablet ? 6.0 : 8.0;
                          final double mainAxisSpacing = isTabletPortrait
                              ? 16.0
                              : (isTablet ? 6.0 : 18.0);
                          final double imageHeight = isTabletPortrait
                              ? 262.0
                              : (isTablet ? 132.0 : 155.0);

                          if (isTabletPortrait) {
                            final double availableWidth = constraints.maxWidth -
                                16 -
                                (3 * crossAxisSpacing);
                            final double itemWidth = availableWidth / 4;
                            final double itemHeight = imageHeight + 95;
                            return GridView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 6,
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: itemWidth + 1,
                                mainAxisExtent: itemHeight,
                                mainAxisSpacing: mainAxisSpacing,
                                crossAxisSpacing: crossAxisSpacing,
                              ),
                              itemBuilder: (ctx, i) => ProductCardShimmer(
                                portraitImageHeight: imageHeight,
                                scaleFactor: 0.9,
                              ),
                            );
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: 6,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isTablet ? 5 : 2,
                              mainAxisSpacing: mainAxisSpacing,
                              crossAxisSpacing: crossAxisSpacing,
                              childAspectRatio: isTablet ? 0.50 : 0.46,
                            ),
                            itemBuilder: (ctx, i) => ProductCardShimmer(
                              portraitImageHeight: imageHeight,
                              scaleFactor: isTablet ? 0.9 : 1.0,
                            ),
                          );
                        },
                      ),
                    )
                  else if (_displayProducts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isTablet = constraints.maxWidth >= 600;
                          final bool isLandscape =
                              MediaQuery.of(context).orientation ==
                                  Orientation.landscape;
                          final bool isTabletPortrait =
                              isTablet && !isLandscape;
                          final double crossAxisSpacing = isTablet ? 6.0 : 8.0;
                          final double mainAxisSpacing = isTabletPortrait
                              ? 16.0
                              : (isTablet ? 6.0 : 18.0);
                          final double imageHeight = isTabletPortrait
                              ? 262.0
                              : (isTablet ? 132.0 : 155.0);

                          if (isTabletPortrait) {
                            final double availableWidth = constraints.maxWidth -
                                16 -
                                (3 * crossAxisSpacing);
                            final double itemWidth = availableWidth / 4;
                            final double itemHeight = imageHeight + 95;
                            return GridView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _displayProducts.length,
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: itemWidth + 1,
                                mainAxisExtent: itemHeight,
                                mainAxisSpacing: mainAxisSpacing,
                                crossAxisSpacing: crossAxisSpacing,
                              ),
                              itemBuilder: (ctx, i) {
                                final prod = _displayProducts[i];
                                return ProductCard(
                                  key: ValueKey(prod.id),
                                  product: prod,
                                  scaleFactor: 0.9,
                                  internalScaleFactor: 1.0,
                                  portraitImageHeight: imageHeight,
                                );
                              },
                            );
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _displayProducts.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isTablet ? 5 : 2,
                              mainAxisSpacing: mainAxisSpacing,
                              crossAxisSpacing: crossAxisSpacing,
                              childAspectRatio: isTablet ? 0.50 : 0.46,
                            ),
                            itemBuilder: (ctx, i) {
                              final prod = _displayProducts[i];
                              return ProductCard(
                                key: ValueKey(prod.id),
                                product: prod,
                                scaleFactor: isTablet ? 0.9 : 1.0,
                                internalScaleFactor: 1.0,
                                portraitImageHeight: imageHeight,
                              );
                            },
                          );
                        },
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
}