// lib/screens/dynamic_filter_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/brands.dart';
import '../../utils/color_localization.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../constants/all_in_one_category_data.dart'; // Add this import

class DynamicFilterScreen extends StatefulWidget {
  final String category;
  final String? subcategory; // Add this to get current subcategory
  final String? buyerCategory; // Add this to check if it's Women/Men
  final List<String>? initialBrands;
  final List<String>? initialColors;
  final List<String>?
      initialSubSubcategories; // Add this for seller subsubcategories
  /// Currently selected spec filters: field name → selected values
  final Map<String, List<String>>? initialSpecFilters;
  /// Available spec facets from Typesense: field name → list of {'value': '...', 'count': N}
  final Map<String, List<Map<String, dynamic>>> availableSpecFacets;
  final double? initialMinPrice;
  final double? initialMaxPrice;

  const DynamicFilterScreen({
    Key? key,
    required this.category,
    this.subcategory,
    this.buyerCategory,
    this.initialBrands,
    this.initialColors,
    this.initialSubSubcategories,
    this.initialSpecFilters,
    this.availableSpecFacets = const {},
    this.initialMinPrice,
    this.initialMaxPrice,
  }) : super(key: key);

  @override
  _DynamicFilterScreenState createState() => _DynamicFilterScreenState();
}

class _DynamicFilterScreenState extends State<DynamicFilterScreen> {
  List _brands = [];
  List<String> _selectedBrands = [];
  List<String> _selectedColors = [];
  List<String> _selectedSubSubcategories =
      []; // Add this for seller subsubcategories
  /// Generic spec filters: field name → selected values
  Map<String, List<String>> _selectedSpecFilters = {};
  double? _minPrice;
  double? _maxPrice;

  bool _isBrandExpanded = false;
  bool _isColorExpanded = false;
  bool _isCategoriesExpanded = false; // Add this for categories expansion
  /// Track expansion state per spec facet field
  final Map<String, bool> _specFieldExpanded = {};
  bool _isPriceExpanded = false;

  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  TextEditingController _brandSearchController = TextEditingController();
  List<String> _filteredBrands = [];

  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blue', 'color': Colors.blue},
    {'name': 'Orange', 'color': Colors.orange},
    {'name': 'Yellow', 'color': Colors.yellow},
    {'name': 'Black', 'color': Colors.black},
    {'name': 'Brown', 'color': Colors.brown},
    {'name': 'Dark Blue', 'color': const Color(0xFF00008B)},
    {'name': 'Gray', 'color': Colors.grey},
    {'name': 'Pink', 'color': Colors.pink},
    {'name': 'Red', 'color': Colors.red},
    {'name': 'White', 'color': Colors.white},
    {'name': 'Green', 'color': Colors.green},
    {'name': 'Purple', 'color': Colors.purple},
    {'name': 'Teal', 'color': Colors.teal},
    {'name': 'Lime', 'color': Colors.lime},
    {'name': 'Cyan', 'color': Colors.cyan},
    {'name': 'Magenta', 'color': const Color(0xFFFF00FF)},
    {'name': 'Indigo', 'color': Colors.indigo},
    {'name': 'Amber', 'color': Colors.amber},
    {'name': 'Deep Orange', 'color': Colors.deepOrange},
    {'name': 'Light Blue', 'color': Colors.lightBlue},
    {'name': 'Deep Purple', 'color': Colors.deepPurple},
    {'name': 'Light Green', 'color': Colors.lightGreen},
    {'name': 'Dark Gray', 'color': const Color(0xFF444444)},
    {'name': 'Beige', 'color': const Color(0xFFF5F5DC)},
    {'name': 'Turquoise', 'color': const Color(0xFF40E0D0)},
    {'name': 'Violet', 'color': const Color(0xFFEE82EE)},
    {'name': 'Olive', 'color': const Color(0xFF808000)},
    {'name': 'Maroon', 'color': const Color(0xFF800000)},
    {'name': 'Navy', 'color': const Color(0xFF000080)},
    {'name': 'Silver', 'color': const Color(0xFFC0C0C0)},
  ];

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _initializeFilters();
    _filteredBrands = List.from(_brands);
  }

  void _filterBrands(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBrands = _brands.cast<String>(); // Cast to List<String>
      } else {
        _filteredBrands = _brands
            .cast<String>() // Cast to String first
            .where((brand) => brand.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _initializeFilters() {
    _selectedBrands = widget.initialBrands != null
        ? List.from(widget.initialBrands!)
        : <String>[];
    _selectedColors = widget.initialColors != null
        ? List.from(widget.initialColors!)
        : <String>[];
    _selectedSubSubcategories = widget.initialSubSubcategories != null
        ? List.from(widget.initialSubSubcategories!)
        : <String>[];
    if (widget.initialSpecFilters != null) {
      _selectedSpecFilters = widget.initialSpecFilters!.map(
        (k, v) => MapEntry(k, List<String>.from(v)),
      );
    } else {
      _selectedSpecFilters = {};
    }
    _minPrice = widget.initialMinPrice;
    _maxPrice = widget.initialMaxPrice;

    _minPriceController.text = _minPrice?.toString() ?? '';
    _maxPriceController.text = _maxPrice?.toString() ?? '';
  }

  /// Check if categories filter should be shown (only for Women/Men buyer categories)
  bool _shouldShowCategoriesFilter() {
    return widget.buyerCategory == 'Women' || widget.buyerCategory == 'Men';
  }

  /// Get available subsubcategories (seller's subsubcategories) for current subcategory
  List<String> _getAvailableSubSubcategories() {
    if (!_shouldShowCategoriesFilter() || widget.subcategory == null) {
      return [];
    }

    // Get subsubcategories from the category data
    final subSubcategoriesMap =
        AllInOneCategoryData.kSubSubcategories[widget.category];

    if (subSubcategoriesMap != null) {
      final subSubcategories = subSubcategoriesMap[widget.subcategory] ?? [];

      return subSubcategories;
    }

    return [];
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

  void _loadBrands() {
    // Use the single global brands list for all categories
    _brands = globalBrands;
  }

  int _getTotalSelected() {
    int count = 0;
    count += _selectedBrands.length;
    count += _selectedColors.length;
    count += _selectedSubSubcategories.length;
    for (final vals in _selectedSpecFilters.values) {
      count += vals.length;
    }
    if (_minPrice != null || _maxPrice != null) count++;
    return count;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedBrands.clear();
      _selectedColors.clear();
      _selectedSubSubcategories.clear();
      _selectedSpecFilters.clear();
      _minPrice = null;
      _maxPrice = null;
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  void _updatePriceFromController() {
    final minText = _minPriceController.text.trim();
    final maxText = _maxPriceController.text.trim();

    setState(() {
      _minPrice = minText.isNotEmpty ? double.tryParse(minText) : null;
      _maxPrice = maxText.isNotEmpty ? double.tryParse(maxText) : null;
    });
  }

  bool _validatePriceRange() {
    if (_minPrice != null && _maxPrice != null) {
      return _minPrice! <= _maxPrice!;
    }
    return true;
  }

  void _showPriceError(AppLocalizations l10n) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_getSafeLocalizedString(() => l10n.invalidPriceRange,
            'Minimum price cannot be greater than maximum price')),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final availableSubSubcategories = _getAvailableSubSubcategories();
    final availableSpecFacets = widget.availableSpecFacets;

    print("DynamicFilterScreen Debug Info:");
    print("   category: ${widget.category}");
    print("   subcategory: ${widget.subcategory}");
    print("   buyerCategory: ${widget.buyerCategory}");
    print("   _shouldShowCategoriesFilter(): ${_shouldShowCategoriesFilter()}");
    print("   availableSubSubcategories: $availableSubSubcategories");
    print(
        "   availableSubSubcategories.isNotEmpty: ${availableSubSubcategories.isNotEmpty}");
    print(
        "   availableSpecFacets fields: ${availableSpecFacets.keys.toList()}");

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_getSafeLocalizedString(() => l10n.filter, 'Filter')),
        actions: [
          TextButton(
            onPressed: _clearAllFilters,
            child: Text(
              _getSafeLocalizedString(() => l10n.clear, 'Clear'),
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Categories Filter (only for Women/Men buyer categories)
                  if (_shouldShowCategoriesFilter() &&
                      availableSubSubcategories.isNotEmpty) ...[
                    ExpansionTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getSafeLocalizedString(
                                () => l10n.categories, 'Categories'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_selectedSubSubcategories.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedSubSubcategories.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        _isCategoriesExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.orange,
                      ),
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _isCategoriesExpanded = expanded;
                        });
                      },
                      children: [
                        // Clear categories option
                        ListTile(
                          title: Text(
                            _getSafeLocalizedString(() => l10n.clearCategories,
                                'Clear All Categories'),
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.orange,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedSubSubcategories.clear();
                            });
                          },
                          trailing: _selectedSubSubcategories.isNotEmpty
                              ? const Icon(Icons.clear, color: Colors.orange)
                              : null,
                        ),
                        const Divider(height: 1),
                        // Category options - now with checkboxes for multiple selection
                        ...availableSubSubcategories.map((subSubcategory) {
                          // Get the product category to use for localization
                          final localizedName =
                              AllInOneCategoryData.localizeSubSubcategoryKey(
                            widget
                                .category, // The product category (e.g., "Clothing & Fashion")
                            widget
                                .subcategory!, // The product subcategory (e.g., "Dresses")
                            subSubcategory, // The sub-subcategory (e.g., "Casual Dresses")
                            l10n,
                          );

                          return CheckboxListTile(
                            title: Text(localizedName),
                            value: _selectedSubSubcategories
                                .contains(subSubcategory),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedSubSubcategories.add(subSubcategory);
                                } else {
                                  _selectedSubSubcategories
                                      .remove(subSubcategory);
                                }
                              });
                            },
                            activeColor: Colors.orange,
                          );
                        }).toList(),
                      ],
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey[300],
                    ),
                  ],

                  // Dynamic Spec Filter Sections (facet-driven from Typesense)
                  // One section per facet field that has data
                  ...availableSpecFacets.entries.map((specEntry) {
                    final fieldName = specEntry.key;
                    final facetValues = specEntry.value;
                    if (facetValues.isEmpty) return const SizedBox.shrink();

                    final selectedForField =
                        _selectedSpecFilters[fieldName] ?? [];
                    final isExpanded =
                        _specFieldExpanded[fieldName] ?? false;
                    final sectionTitle =
                        AttributeLocalizationUtils.getLocalizedAttributeTitle(
                            fieldName, l10n);

                    return Column(
                      children: [
                        ExpansionTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                sectionTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selectedForField.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${selectedForField.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.orange,
                          ),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              _specFieldExpanded[fieldName] = expanded;
                            });
                          },
                          children: [
                            // Clear option
                            ListTile(
                              title: Text(
                                _getSafeLocalizedString(
                                    () => l10n.clearAll, 'Clear All'),
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.orange,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedSpecFilters.remove(fieldName);
                                });
                              },
                              trailing: selectedForField.isNotEmpty
                                  ? const Icon(Icons.clear,
                                      color: Colors.orange)
                                  : null,
                            ),
                            const Divider(height: 1),
                            // Facet value options
                            Container(
                              height:
                                  facetValues.length > 8 ? 300 : null,
                              child: ListView.builder(
                                shrinkWrap: facetValues.length <= 8,
                                physics: facetValues.length <= 8
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                itemCount: facetValues.length,
                                itemBuilder: (context, index) {
                                  final facet = facetValues[index];
                                  final value = facet['value'] as String;
                                  final count = facet['count'] as int;
                                  final localizedName =
                                      AttributeLocalizationUtils
                                          .getLocalizedSingleValue(
                                              fieldName, value, l10n);

                                  return CheckboxListTile(
                                    title:
                                        Text('$localizedName ($count)'),
                                    value:
                                        selectedForField.contains(value),
                                    onChanged: (selected) {
                                      setState(() {
                                        final list =
                                            _selectedSpecFilters[
                                                    fieldName] ??=
                                                [];
                                        if (selected == true) {
                                          if (!list.contains(value)) {
                                            list.add(value);
                                          }
                                        } else {
                                          list.remove(value);
                                          if (list.isEmpty) {
                                            _selectedSpecFilters
                                                .remove(fieldName);
                                          }
                                        }
                                      });
                                    },
                                    activeColor: Colors.orange,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey[300],
                        ),
                      ],
                    );
                  }),

                  // Brand Filter
                  if (_brands.isNotEmpty) ...[
                    ExpansionTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getSafeLocalizedString(() => l10n.brand, 'Brand'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_selectedBrands.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedBrands.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        _isBrandExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.orange,
                      ),
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _isBrandExpanded = expanded;
                        });
                      },
                      children: [
                        // Clear brands option
                        ListTile(
                          title: Text(
                            _getSafeLocalizedString(
                                () => l10n.clearBrands, 'Clear All Brands'),
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.orange,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedBrands.clear();
                            });
                          },
                          trailing: _selectedBrands.isNotEmpty
                              ? const Icon(Icons.clear, color: Colors.orange)
                              : null,
                        ),

                        // ⭐ ADD SEARCH BAR
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: TextField(
                            controller: _brandSearchController,
                            decoration: InputDecoration(
                              hintText: _getSafeLocalizedString(
                                  () => l10n.search, 'Search'),
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Colors.orange),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            onChanged: _filterBrands,
                          ),
                        ),

                        const Divider(height: 1),

                        // ⭐ OPTIMIZED: Use filtered list with ListView.builder
                        Container(
                          height: 300,
                          child: ListView.builder(
                            itemCount: _filteredBrands.length,
                            itemBuilder: (context, index) {
                              final brand = _filteredBrands[index];
                              return CheckboxListTile(
                                title: Text(brand),
                                value: _selectedBrands.contains(brand),
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedBrands.add(brand);
                                    } else {
                                      _selectedBrands.remove(brand);
                                    }
                                  });
                                },
                                activeColor: Colors.orange,
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  ],
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey[300],
                  ),
                  // Color Filter
                  ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getSafeLocalizedString(() => l10n.color, 'Color'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_selectedColors.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_selectedColors.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Icon(
                      _isColorExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.orange,
                    ),
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _isColorExpanded = expanded;
                      });
                    },
                    children: [
                      // Clear colors option
                      ListTile(
                        title: Text(
                          _getSafeLocalizedString(
                              () => l10n.clearColors, 'Clear All Colors'),
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.orange,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedColors.clear();
                          });
                        },
                        trailing: _selectedColors.isNotEmpty
                            ? const Icon(Icons.clear, color: Colors.orange)
                            : null,
                      ),
                      const Divider(height: 1),
                      // Color options
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _availableColors.length,
                          itemBuilder: (context, index) {
                            final colorData = _availableColors[index];
                            final name = colorData['name'] as String;
                            final value = colorData['color'] as Color;
                            final localized =
                                ColorLocalization.localizeColorName(name, l10n);
                            final isSelected = _selectedColors.contains(name);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedColors.remove(name);
                                  } else {
                                    _selectedColors.add(name);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.orange.withOpacity(0.1)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.orange
                                        : Colors.grey[300]!,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: value,
                                        border: Border.all(
                                          color: Colors.grey[400]!,
                                          width: value == Colors.white ? 2 : 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        localized,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check,
                                        color: Colors.orange,
                                        size: 16,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey[300],
                  ),

                  // Price Range Filter
                  ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getSafeLocalizedString(
                              () => l10n.priceRange2, 'Price Range'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_minPrice != null || _maxPrice != null)
                          const Icon(Icons.check,
                              color: Colors.orange, size: 20),
                      ],
                    ),
                    trailing: Icon(
                      _isPriceExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.orange,
                    ),
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _isPriceExpanded = expanded;
                      });
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Current price display
                            if (_minPrice != null || _maxPrice != null)
                              Container(
                                padding: const EdgeInsets.all(8),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline,
                                        color: Colors.orange, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_minPrice?.toStringAsFixed(0) ?? '0'} - ${_maxPrice?.toStringAsFixed(0) ?? '∞'} TL',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _minPrice = null;
                                          _maxPrice = null;
                                          _minPriceController.clear();
                                          _maxPriceController.clear();
                                        });
                                      },
                                      child: const Icon(Icons.close,
                                          color: Colors.orange, size: 16),
                                    ),
                                  ],
                                ),
                              ),

                            // Price input fields
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _minPriceController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d*'),
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: _getSafeLocalizedString(
                                          () => l10n.minPrice, 'Min Price'),
                                      hintText: '0',
                                      suffixText: 'TL',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Colors.orange),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                    ),
                                    onChanged: (_) =>
                                        _updatePriceFromController(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextField(
                                    controller: _maxPriceController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d*'),
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: _getSafeLocalizedString(
                                          () => l10n.maxPrice, 'Max Price'),
                                      hintText: '∞',
                                      suffixText: 'TL',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Colors.orange),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                    ),
                                    onChanged: (_) =>
                                        _updatePriceFromController(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Quick price buttons
                            Text(
                              _getSafeLocalizedString(
                                  () => l10n.quickPriceRanges,
                                  'Quick Price Ranges'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildPriceChip('0 - 100 TL', 0, 100),
                                _buildPriceChip('100 - 500 TL', 100, 500),
                                _buildPriceChip('500 - 1000 TL', 500, 1000),
                                _buildPriceChip('1000+ TL', 1000, null),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (!_validatePriceRange()) {
                      _showPriceError(l10n);
                      return;
                    }

                    Navigator.pop(context, {
                      'brands': _selectedBrands,
                      'colors': _selectedColors,
                      'subSubcategories': _selectedSubSubcategories,
                      'specFilters': _selectedSpecFilters,
                      'minPrice': _minPrice,
                      'maxPrice': _maxPrice,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                  ),
                  child: Text(
                    '${_getSafeLocalizedString(() => l10n.apply, 'Apply')} ${_getTotalSelected() > 0 ? '(${_getTotalSelected()})' : ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceChip(String label, double? min, double? max) {
    final isSelected = _minPrice == min && _maxPrice == max;

    return GestureDetector(
      onTap: () {
        setState(() {
          _minPrice = min;
          _maxPrice = max;
          _minPriceController.text = min?.toString() ?? '';
          _maxPriceController.text = max?.toString() ?? '';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
