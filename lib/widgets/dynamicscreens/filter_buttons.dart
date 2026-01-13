import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class FilterButtons extends StatelessWidget {
  /// Category context for dynamic filter screen
  final String category;
  final String? subsubcategory;
  final String? subcategory; // Add this parameter
  final String? buyerCategory;

  /// Simple filter
  final String? selectedFilter;
  final ValueChanged<String?> onFilterSelected;
  final ScrollController? scrollController;

  /// Dynamic filter state - Updated to support multiple brands
  final List<String> dynamicBrands;
  final List<String> dynamicColors;
  final List<String> dynamicSubSubcategories;
  final double? minPrice;
  final double? maxPrice;

  /// Called when user applies a dynamic filter
  final ValueChanged<Map<String, dynamic>>? onDynamicApplied;

  const FilterButtons({
    Key? key,
    required this.category,
    this.subsubcategory,
    this.subcategory,
    this.buyerCategory,
    required this.selectedFilter,
    required this.onFilterSelected,
    this.scrollController,
    this.dynamicBrands = const [],
    this.dynamicColors = const [],
    this.dynamicSubSubcategories = const [],
    this.minPrice,
    this.maxPrice,
    this.onDynamicApplied,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Count how many dynamic filters are active
    final int appliedCount = dynamicBrands.length +
        dynamicColors.length +
        dynamicSubSubcategories.length +
        (minPrice != null || maxPrice != null ? 1 : 0);
    final bool hasApplied = appliedCount > 0;
    final String filterLabel =
        hasApplied ? '${l10n.filter} ($appliedCount)' : l10n.filter;

    // Quick filters with fallback texts
    final List<Map<String, String>> filters = [
      {
        'key': 'deals',
        'label': _getSafeLocalizedString(() => l10n.deals, 'Deals')
      },
      {
        'key': 'boosted',
        'label': _getSafeLocalizedString(() => l10n.boosted, 'Boosted')
      },
      {
        'key': 'trending',
        'label': _getSafeLocalizedString(() => l10n.trending, 'Trending')
      },
      {
        'key': 'fiveStar',
        'label': _getSafeLocalizedString(() => l10n.fiveStar, '5★')
      },
      {
        'key': 'bestSellers',
        'label': _getSafeLocalizedString(() => l10n.bestSellers, 'Best Sellers')
      },
    ];

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          // — Dynamic Filter pill —
          GestureDetector(
            onTap: () async {
              final result = await context.push('/dynamic_filter', extra: {
                'category': category,
                'subcategory': subcategory, // Add this line
                'buyerCategory': buyerCategory, // Add this line
                'initialBrands': dynamicBrands,
                'initialColors': dynamicColors,
                'initialSubSubcategories':
                    dynamicSubSubcategories, // Add this line
                'initialMinPrice': minPrice,
                'initialMaxPrice': maxPrice,
              });
              if (result is Map<String, dynamic>) {
                onDynamicApplied?.call(result);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: hasApplied ? Colors.orange : Colors.transparent,
                border: Border.all(
                  color: hasApplied ? Colors.orange : Colors.grey.shade300,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune,
                    size: 14,
                    color: hasApplied
                        ? Colors.white
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    filterLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasApplied
                          ? Colors.white
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 4),

          // — Scrollable quick filters —
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              controller: scrollController,
              physics: const BouncingScrollPhysics(),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final filter = filters[index];
                final bool isSelected = selectedFilter == filter['key'];
                return GestureDetector(
                  onTap: () {
                    onFilterSelected(isSelected ? null : filter['key']!);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orange : Colors.transparent,
                      border: Border.all(
                        color:
                            isSelected ? Colors.orange : Colors.grey.shade300,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Center(
                      child: Text(
                        filter['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Safe method to get localized strings that might be functions
  String _getSafeLocalizedString(dynamic Function() getter, String fallback) {
    try {
      final result = getter();
      if (result is String) {
        return result;
      } else {
        return fallback;
      }
    } catch (e) {
      return fallback;
    }
  }
}
