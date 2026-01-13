import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/brands.dart';
import '../../constants/all_in_one_category_data.dart';

class DynamicSubcategoryFilterScreen extends StatefulWidget {
  final String category;
  final String subcategoryId;
  final String subcategoryName;
  final String? initialBrand;
  final List<String>? initialColors;
  final String? initialSubsubcategory;
  final bool isGenderFilter; // Add this
  final String? gender;

  const DynamicSubcategoryFilterScreen({
    Key? key,
    required this.category,
    required this.subcategoryId,
    required this.subcategoryName,
    this.initialBrand,
    this.initialColors,
    this.initialSubsubcategory,
    this.isGenderFilter = false, // Add this
    this.gender,
  }) : super(key: key);

  @override
  _DynamicSubcategoryFilterScreenState createState() =>
      _DynamicSubcategoryFilterScreenState();
}

class _DynamicSubcategoryFilterScreenState
    extends State<DynamicSubcategoryFilterScreen> {
  List _brands = [];
  String? _selectedBrand;
  List<String> _selectedColors = [];
  String? _selectedSubsubcategory;
  bool _isSubsubcategoryExpanded = false;
  bool _isBrandExpanded = false;
  bool _isColorExpanded = false;

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

  List<String> _subsubcategories = [];

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _loadSubsubcategories();
    _selectedBrand = widget.initialBrand;
    _selectedColors = widget.initialColors != null
        ? List.from(widget.initialColors!)
        : <String>[];
    _selectedSubsubcategory = widget.initialSubsubcategory;
    _filteredBrands = List.from(_brands);
  }

  void _loadBrands() {
    // Use the single global brands list for all categories
    // This provides access to all 3000+ brands regardless of category
    _brands = globalBrands;
  }

  void _filterBrands(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBrands = _brands.cast<String>();
      } else {
        _filteredBrands = _brands
            .cast<String>()
            .where((brand) => brand.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _loadSubsubcategories() {
    // Check if this is a buyer category (Women/Men)
    if (widget.category == 'Women' || widget.category == 'Men') {
      // Map buyer subcategory to product category
      final mapping =
          AllInOneCategoryData.kBuyerToProductCategoryMapping[widget.category];
      if (mapping != null && mapping.containsKey(widget.subcategoryId)) {
        final productCategory = mapping[widget.subcategoryId]!;

        // Get the product subcategories (these become our filter options)
        // For "Fashion" → ["Dresses", "Tops & Shirts", "Bottoms", "Outerwear", ...]
        _subsubcategories =
            AllInOneCategoryData.kSubcategories[productCategory] ?? [];

        if (_subsubcategories.isNotEmpty) {}
      } else {
        _subsubcategories = [];
      }
    }
    // Check if category is a top-level product category (Clothing & Fashion, Footwear, etc.)
    else if (AllInOneCategoryData.kSubcategories.containsKey(widget.category)) {
      // Get subcategories directly from the product category
      _subsubcategories =
          AllInOneCategoryData.kSubcategories[widget.category] ?? [];

      if (_subsubcategories.isNotEmpty) {}
    } else {
      // Regular subcategory - get actual sub-subcategories
      final subsubcategoriesMap =
          AllInOneCategoryData.kSubSubcategories[widget.category];

      if (subsubcategoriesMap != null) {
        _subsubcategories = subsubcategoriesMap[widget.subcategoryId] ?? [];
      } else {
        _subsubcategories = [];
      }
    }
  }

  String _localizeColorName(String name, AppLocalizations l10n) {
    switch (name) {
      case 'Blue':
        return l10n.colorBlue;
      case 'Orange':
        return l10n.colorOrange;
      case 'Yellow':
        return l10n.colorYellow;
      case 'Black':
        return l10n.colorBlack;
      case 'Brown':
        return l10n.colorBrown;
      case 'Dark Blue':
        return l10n.colorDarkBlue;
      case 'Gray':
        return l10n.colorGray;
      case 'Pink':
        return l10n.colorPink;
      case 'Red':
        return l10n.colorRed;
      case 'White':
        return l10n.colorWhite;
      case 'Green':
        return l10n.colorGreen;
      case 'Purple':
        return l10n.colorPurple;
      case 'Teal':
        return l10n.colorTeal;
      case 'Lime':
        return l10n.colorLime;
      case 'Cyan':
        return l10n.colorCyan;
      case 'Magenta':
        return l10n.colorMagenta;
      case 'Indigo':
        return l10n.colorIndigo;
      case 'Amber':
        return l10n.colorAmber;
      case 'Deep Orange':
        return l10n.colorDeepOrange;
      case 'Light Blue':
        return l10n.colorLightBlue;
      case 'Deep Purple':
        return l10n.colorDeepPurple;
      case 'Light Green':
        return l10n.colorLightGreen;
      case 'Dark Gray':
        return l10n.colorDarkGray;
      case 'Beige':
        return l10n.colorBeige;
      case 'Turquoise':
        return l10n.colorTurquoise;
      case 'Violet':
        return l10n.colorViolet;
      case 'Olive':
        return l10n.colorOlive;
      case 'Maroon':
        return l10n.colorMaroon;
      case 'Navy':
        return l10n.colorNavy;
      case 'Silver':
        return l10n.colorSilver;
      default:
        return name;
    }
  }

  int _getTotalSelected() {
    int count = _selectedColors.length;
    if (_selectedBrand != null) count += 1;
    if (_selectedSubsubcategory != null) count += 1;
    return count;
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
                _selectedBrand = null;
                _selectedColors.clear();
                _selectedSubsubcategory = null;
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
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Subsubcategory Filter
                  ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.category),
                        if (_selectedSubsubcategory != null)
                          const Icon(Icons.check, color: Colors.orange),
                      ],
                    ),
                    trailing: Icon(
                      _isSubsubcategoryExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.orange,
                    ),
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _isSubsubcategoryExpanded = expanded;
                      });
                    },
                    children: _subsubcategories.map((subsubcategory) {
                      // Determine how to localize based on context
                      String localizedName;

                      if (widget.category == 'Women' ||
                          widget.category == 'Men') {
                        // For buyer categories, these are product subcategories
                        final productCategory = AllInOneCategoryData
                                .kBuyerToProductCategoryMapping[widget.category]
                            ?[widget.subcategoryId];

                        if (productCategory != null) {
                          localizedName =
                              AllInOneCategoryData.localizeSubcategoryKey(
                            productCategory,
                            subsubcategory,
                            l10n,
                          );
                        } else {
                          localizedName = subsubcategory;
                        }
                      }
                      // Check if category is a top-level product category
                      else if (AllInOneCategoryData.kSubcategories
                          .containsKey(widget.category)) {
                        // For top-level product categories, localize as subcategories
                        localizedName =
                            AllInOneCategoryData.localizeSubcategoryKey(
                          widget.category,
                          subsubcategory,
                          l10n,
                        );
                      } else {
                        // For regular subcategories, these are sub-subcategories
                        localizedName =
                            AllInOneCategoryData.localizeSubSubcategoryKey(
                          widget.category,
                          widget.subcategoryId,
                          subsubcategory,
                          l10n,
                        );
                      }

                      return RadioListTile(
                        title: Text(localizedName),
                        value: subsubcategory,
                        groupValue: _selectedSubsubcategory,
                        onChanged: (value) {
                          setState(() {
                            _selectedSubsubcategory = value;
                          });
                        },
                        activeColor: Colors.orange,
                      );
                    }).toList(),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey[300],
                  ),
                  // Brand Filter
                  ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.brand),
                        if (_selectedBrand != null)
                          const Icon(Icons.check, color: Colors.orange),
                      ],
                    ),
                    trailing: Icon(
                      _isBrandExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.orange,
                    ),
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _isBrandExpanded = expanded;
                      });
                    },
                    children: [
                      // Clear brand option
                      ListTile(
                        title: Text(
                          l10n.clearBrands,
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.orange,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedBrand = null;
                          });
                        },
                        trailing: _selectedBrand != null
                            ? const Icon(Icons.clear, color: Colors.orange)
                            : null,
                      ),

                      // Search bar
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _brandSearchController,
                          decoration: InputDecoration(
                            hintText: l10n.search, // or 'Search'
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

                      // Filtered brands list
                      Container(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _filteredBrands.length,
                          itemBuilder: (context, index) {
                            final brand = _filteredBrands[index];
                            return RadioListTile(
                              title: Text(brand),
                              value: brand,
                              groupValue: _selectedBrand,
                              onChanged: (value) {
                                setState(() {
                                  _selectedBrand = value;
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
                  // Color Filter
                  ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.color),
                        if (_selectedColors.isNotEmpty)
                          Text(
                            '(${_selectedColors.length})',
                            style: const TextStyle(color: Colors.orange),
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
                            final localized = _localizeColorName(name, l10n);
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
                ],
              ),
            ),
          ),
          // Apply Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'brand': _selectedBrand,
                    'colors': _selectedColors,
                    'subsubcategory': _selectedSubsubcategory,
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
                  '${l10n.apply} (${_getTotalSelected()})',
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
