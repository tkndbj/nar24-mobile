import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class SubcategoryFilterButtons extends StatelessWidget {
  /// Category context for dynamic filter screen
  final String category;
  final String? subcategoryId;
  final String? subcategoryName;
  final String? dynamicSubsubcategory;

  /// Simple filter
  final String? selectedFilter;
  final ValueChanged<String?> onFilterSelected;
  final ScrollController? scrollController;

  /// Dynamic filter state
  final String? dynamicBrand;
  final List<String> dynamicColors;

  /// Called when user applies a dynamic filter
  final ValueChanged<Map<String, dynamic>>? onDynamicApplied;

  const SubcategoryFilterButtons({
    Key? key,
    required this.category,
    this.subcategoryId,
    this.subcategoryName,
    this.dynamicSubsubcategory,
    required this.selectedFilter,
    required this.onFilterSelected,
    this.scrollController,
    this.dynamicBrand,
    this.dynamicColors = const [],
    this.onDynamicApplied,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Count how many dynamic filters are active
    final int appliedCount =
        (dynamicBrand != null ? 1 : 0) + dynamicColors.length;
    final bool hasApplied = appliedCount > 0;
    final String filterLabel =
        hasApplied ? '${l10n.filter} ($appliedCount)' : l10n.filter;

    // Quick filters
    final List<Map<String, String>> filters = [
      {'key': 'deals', 'label': l10n.deals},
      {'key': 'boosted', 'label': l10n.boosted},
      {'key': 'trending', 'label': l10n.trending},
      {'key': 'fiveStar', 'label': l10n.fiveStar},
      {'key': 'bestSellers', 'label': l10n.bestSellers},
    ];

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          // Dynamic Filter pill
          GestureDetector(
            onTap: () async {
              final result =
                  await context.push('/dynamic_subcategory_filter', extra: {
                'category': category,
                'subcategoryId': subcategoryId,
                'initialBrand': dynamicBrand,
                'initialColors': dynamicColors,
                'initialSubsubcategory': dynamicSubsubcategory,
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
              child: Center(
                child: Text(
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
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Scrollable quick filters
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
}
