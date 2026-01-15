import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/shop_widget_provider.dart';
import '../providers/special_filter_provider_market.dart';
import '../providers/market_dynamic_filter_provider.dart';
import '../generated/l10n/app_localizations.dart';
import '../screens/market_screen.dart';
import '../models/dynamic_filter.dart';
import 'package:shimmer/shimmer.dart';

class FilterItem {
  final String label;
  final String type;
  final bool isDynamic;
  final DynamicFilter? dynamicFilter;

  const FilterItem({
    required this.label,
    required this.type,
    this.isDynamic = false,
    this.dynamicFilter,
  });
}

class FilterSortRow extends StatefulWidget {
  final ScrollController? scrollController;
  final Color backgroundColor;
  final bool animate;
  final Color textColor;

  const FilterSortRow({
    Key? key,
    this.scrollController,
    required this.backgroundColor,
    required this.animate,
    required this.textColor,
  }) : super(key: key);

  @override
  State<FilterSortRow> createState() => _FilterSortRowState();
}

class _FilterSortRowState extends State<FilterSortRow> {
  static const List<Color> sellerGradientColors = [Colors.purple, Colors.pink];

  // OPTIMIZATION 1: Cache localization and market state
  AppLocalizations? _l10n;
  MarketScreenState? _marketState;
  String? _cachedLocale; // OPTIMIZED: Cache locale to avoid repeated tree traversals

  // OPTIMIZATION 2: Cache filter list to avoid rebuilding on every frame
  List<FilterItem>? _cachedFilters;
  String? _lastCacheKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
    _marketState = context.findAncestorStateOfType<MarketScreenState>();
    // OPTIMIZED: Cache locale to avoid repeated Localizations.localeOf() calls
    _cachedLocale = Localizations.localeOf(context).languageCode;
  }

  // OPTIMIZATION 3: Build cache key from provider states
  // Include userShopId to invalidate cache when shop data becomes available
  String _buildCacheKey(bool userHasShop, bool isLoading, bool hasError,
      List<DynamicFilter> activeFilters, {String? userShopId}) {
    // Cache based on shop status, shop ID availability, and filter count
    return '$userHasShop|${userShopId != null}|${activeFilters.length}';
  }

  bool _isLightColor(Color color) {
  // Calculate relative luminance (perceived brightness)
  // Values closer to 1.0 are lighter, closer to 0.0 are darker
  final luminance = color.computeLuminance();
  return luminance > 0.7; // Threshold: 0.7 means quite light
}

  // OPTIMIZATION 4: Cached filter building
  // Now takes shopId to ensure seller panel button has access to it
  List<FilterItem> _buildFilters(bool userHasShop, String? userShopId,
      List<DynamicFilter> activeFilters, DynamicFilterProvider dynamicProv) {
    final cacheKey = _buildCacheKey(
      userHasShop, false, false, activeFilters, userShopId: userShopId);

    if (_cachedFilters != null && _lastCacheKey == cacheKey) {
      return _cachedFilters!;
    }

    final l10n = _l10n!;
    final filters = <FilterItem>[];

    // Add seller panel if user has shop AND we have the shop ID
    if (userHasShop && userShopId != null) {
      filters.add(FilterItem(label: l10n.sellerPanel, type: 'SellerPanel'));
    }

    // Add shops button
    filters.add(FilterItem(label: l10n.shops, type: 'Shops'));

    // Add dynamic filters
    for (final dynamicFilter in activeFilters) {
      // OPTIMIZED: Use cached locale instead of traversing widget tree
      final displayName = dynamicProv.getFilterDisplayName(
        dynamicFilter,
        _cachedLocale ?? 'en',
      );

      filters.add(FilterItem(
        label: displayName,
        type: dynamicFilter.id,
        isDynamic: true,
        dynamicFilter: dynamicFilter,
      ));
    }

    // Add static filters (categories only)
    filters.addAll([
      FilterItem(label: l10n.woman, type: 'Women'),
      FilterItem(label: l10n.man, type: 'Men'),
      FilterItem(label: l10n.electronics, type: 'Electronics'),
      FilterItem(label: l10n.categoryHomeFurniture, type: 'Home & Furniture'),
      FilterItem(label: l10n.categoryMotherChild, type: 'Mother & Child'),
    ]);

    _cachedFilters = filters;
    _lastCacheKey = cacheKey;
    return filters;
  }

  @override
  Widget build(BuildContext context) {
    if (_l10n == null) return const SizedBox.shrink();

    return AnimatedContainer(
      duration:
          widget.animate ? const Duration(milliseconds: 300) : Duration.zero,
      curve: Curves.easeInOut,
      color: widget.backgroundColor,
      padding: const EdgeInsets.only(bottom: 8.0),
      // Listen to ShopWidgetProvider for seller panel button
      child: Selector<ShopWidgetProvider, (bool, String?)>(
        selector: (_, prov) => (prov.userOwnsShop, prov.firstUserShopId),
        builder: (context, shopState, _) {
          final (userOwnsShop, firstUserShopId) = shopState;

          // Then listen to DynamicFilterProvider
          return Selector<DynamicFilterProvider, (bool, String?, int)>(
            selector: (_, prov) => (
              prov.isLoading,
              prov.error,
              prov.activeFilters.length,
            ),
            builder: (context, dynamicState, _) {
              final (isLoading, error, _) = dynamicState;

              // Early returns for loading/error states
              if (isLoading) {
                return _buildLoadingState();
              }

              if (error != null) {
                final dynamicProv =
                    Provider.of<DynamicFilterProvider>(context, listen: false);
                return _buildErrorState(dynamicProv);
              }

              // Get providers without listening (we use Selector for targeted listening)
              final specialProv =
                  Provider.of<SpecialFilterProviderMarket>(context, listen: false);
              final dynamicProv =
                  Provider.of<DynamicFilterProvider>(context, listen: false);

              // Use cached filter building with user's shop ID
              final filters = _buildFilters(
                userOwnsShop,
                firstUserShopId,
                dynamicProv.activeFilters,
                dynamicProv,
              );

              // Use nested Selector for filterType to avoid rebuilds when unrelated data changes
              return Selector<SpecialFilterProviderMarket, String?>(
                selector: (_, prov) => prov.specialFilter,
                builder: (context, filterType, _) {
                  return SizedBox(
                    height: 30,
                    child: ListView.separated(
                      controller: widget.scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(left: 16.0),
                      separatorBuilder: (_, __) => const SizedBox(width: 4),
                      itemCount: filters.length,
                      itemBuilder: (ctx, i) {
                        final f = filters[i];
                        final sel = f.type == filterType;
                        return _buildFilterButton(f, sel, specialProv);
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // OPTIMIZATION 7: Extract widget builders to reduce build method complexity
  Widget _buildLoadingState() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 16.0),
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemCount: 8, // Show 8 shimmer placeholders
        itemBuilder: (ctx, i) {
          // Vary the width for a more natural look
          final widths = [80.0, 100.0, 70.0, 90.0, 110.0, 75.0, 95.0, 85.0];
          final width = widths[i % widths.length];

          return Shimmer.fromColors(
            baseColor: isDarkMode
                ? Color.fromARGB(255, 30, 28, 44)
                : Colors.grey[300]!,
            highlightColor: isDarkMode
                ? Color.fromARGB(255, 33, 31, 49)
                : Colors.grey[100]!,
            child: Container(
              width: width,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(DynamicFilterProvider dynamicProv) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filter yükleme hatası',
              style: TextStyle(
                color: Colors.red.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: dynamicProv.refreshFilters,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 24),
            ),
            child: const Text('Yeniden Dene', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(
      FilterItem f, bool sel, SpecialFilterProviderMarket specialProv) {
    // OPTIMIZATION 8: Use RepaintBoundary for each button
    return RepaintBoundary(
      child: (() {
        if (f.type == 'SellerPanel') {
          return _buildSellerPanelButton(f, sel);
        }
        if (f.isDynamic && f.dynamicFilter != null) {
          return _buildDynamicFilterButton(f, sel, specialProv);
        }
        if (f.type == 'Shops') {
          return _buildShopsButton(f, sel);
        }
        return _buildRegularFilterButton(f, sel, specialProv);
      })(),
    );
  }

  Widget _buildSellerPanelButton(FilterItem f, bool sel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: sellerGradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.0),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(15.5),
            ),
            child: TextButton(
              onPressed: () {
                // Use firstUserShopId - the actual shop ID the user has access to
                final shopProv =
                    Provider.of<ShopWidgetProvider>(context, listen: false);
                final shopId = shopProv.firstUserShopId;
                if (shopId != null) {
                  context.push('/seller-panel?shopId=$shopId');
                } else {
                  // Fallback without shop ID (seller panel will auto-select)
                  context.push('/seller-panel');
                }
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15.5)),
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: sellerGradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : widget.textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

 Widget _buildDynamicFilterButton(
    FilterItem f, bool sel, SpecialFilterProviderMarket specialProv) {
  final filter = f.dynamicFilter!;
  
  // ✅ ADD: Check if background is light
  final isLightBg = _isLightColor(widget.backgroundColor);
  // Determine text/border color based on background
  final unselectedColor = isLightBg ? Colors.black : widget.textColor;
  final unselectedBorderColor = isLightBg ? Colors.grey.shade400 : Colors.grey.shade300;

  return GestureDetector(
    onTap: () {
      debugPrint('🔘 Dynamic filter button tapped: ${f.type}');

      if (_marketState == null) {
        debugPrint('⚠️ MarketState not available, retrying...');
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_marketState != null) {
            _handleDynamicFilterTap(f, filter, specialProv);
          }
        });
        return;
      }

      _handleDynamicFilterTap(f, filter, specialProv);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: sel
            ? (filter.color != null
                ? _parseColor(filter.color!)
                : Colors.orange)
            : Colors.transparent,
        border: Border.all(
          color: sel
              ? (filter.color != null
                  ? _parseColor(filter.color!)
                  : Colors.orange)
              : unselectedBorderColor,  // ✅ UPDATED
          width: 1,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filter.icon != null && filter.icon!.isNotEmpty) ...[
              Text(filter.icon!, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
            ],
            Text(
              f.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : unselectedColor,  // ✅ UPDATED
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  void _handleDynamicFilterTap(FilterItem f, DynamicFilter filter,
      SpecialFilterProviderMarket specialProv) {
    try {
      // Set the filter first
      specialProv.setSpecialFilter(f.type, dynamicFilter: filter);

      // Then try to switch tabs with retry
      if (_marketState != null) {
        _marketState!.switchToFilterTab(f.type);
      } else {
        debugPrint('⚠️ MarketState is null, cannot switch tab');
      }
    } catch (e) {
      debugPrint('❌ Error handling dynamic filter tap: $e');

      // Fallback: just set the filter without tab switching
      try {
        specialProv.setSpecialFilter(f.type, dynamicFilter: filter);
      } catch (e2) {
        debugPrint('❌ Even fallback failed: $e2');
      }
    }
  }

  Widget _buildShopsButton(FilterItem f, bool sel) {
  // ✅ ADD: Check if background is light
  final isLightBg = _isLightColor(widget.backgroundColor);
  final unselectedColor = isLightBg ? Colors.black : widget.textColor;
  final unselectedBorderColor = isLightBg ? Colors.grey.shade400 : Colors.grey.shade300;

  return GestureDetector(
    onTap: () => context.push('/shop'),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: sel ? Colors.orange : Colors.transparent,
        border: Border.all(
          color: sel ? Colors.orange : unselectedBorderColor,  // ✅ UPDATED
          width: 1,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store,
              size: 16,
              color: sel ? Colors.white : unselectedColor,  // ✅ UPDATED
            ),
            const SizedBox(width: 4),
            Text(
              f.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : unselectedColor,  // ✅ UPDATED
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

 Widget _buildRegularFilterButton(
    FilterItem f, bool sel, SpecialFilterProviderMarket specialProv) {
  // ✅ ADD: Check if background is light
  final isLightBg = _isLightColor(widget.backgroundColor);
  final unselectedColor = isLightBg ? Colors.black : widget.textColor;
  final unselectedBorderColor = isLightBg ? Colors.grey.shade400 : Colors.grey.shade300;

  return GestureDetector(
    onTap: () {
      specialProv.setSpecialFilter(f.type);
      _marketState?.switchToFilterTab(f.type);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: sel ? Colors.orange : Colors.transparent,
        border: Border.all(
          color: sel ? Colors.orange : unselectedBorderColor,  // ✅ UPDATED
          width: 1,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Center(
        child: Text(
          f.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: sel ? Colors.white : unselectedColor,  // ✅ UPDATED
          ),
        ),
      ),
    ),
  );
}

  // OPTIMIZATION 9: Cache color parsing
  static final Map<String, Color> _colorCache = <String, Color>{};

  Color _parseColor(String colorString) {
    if (_colorCache.containsKey(colorString)) {
      return _colorCache[colorString]!;
    }

    Color result;
    try {
      final cleanColor = colorString.replaceAll('#', '');
      if (cleanColor.length == 6) {
        result = Color(int.parse('FF$cleanColor', radix: 16));
      } else if (cleanColor.length == 8) {
        result = Color(int.parse(cleanColor, radix: 16));
      } else {
        result = Colors.orange;
      }
    } catch (e) {
      debugPrint('Error parsing color $colorString: $e');
      result = Colors.orange;
    }

    _colorCache[colorString] = result;
    return result;
  }
}
