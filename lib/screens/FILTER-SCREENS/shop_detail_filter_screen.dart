// lib/screens/shop_detail_filter_screen.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../models/product.dart';
import 'package:Nar24/models/mock_document_snapshot.dart';
import 'package:Nar24/constants/brands.dart';
import '../../utils/attribute_localization_utils.dart';

class ShopDetailFilterScreen extends StatefulWidget {
  final MockDocumentSnapshot shopDoc;
  final String? initialGender;
  final List<String> initialTypes;
  final List<String> initialFits;
  final List<String> initialSizes;
  final List<String> initialColors;
  final List<String> initialBrands;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final List<Product> allProducts;
  final Map<String, List<Map<String, dynamic>>> availableSpecFacets;
  final Map<String, List<String>>? initialSpecFilters;

  const ShopDetailFilterScreen({
    Key? key,
    required this.shopDoc,
    this.initialGender,
    required this.initialTypes,
    required this.initialFits,
    required this.initialSizes,
    required this.initialColors,
    this.initialBrands = const [],
    this.initialMinPrice,
    this.initialMaxPrice,
    required this.allProducts,
    this.availableSpecFacets = const {},
    this.initialSpecFilters,
  }) : super(key: key);

  @override
  _ShopDetailFilterScreenState createState() => _ShopDetailFilterScreenState();
}

class _ShopDetailFilterScreenState extends State<ShopDetailFilterScreen> {
  // Filter states
  String? _selectedGender;
  List<String> _selectedBrands = [];
  List<String> _selectedTypes = [];
  List<String> _selectedFits = [];
  List<String> _selectedSizes = [];
  List<String> _selectedColors = [];
  double? _minPrice;
  double? _maxPrice;

  // Dynamic spec filters
  Map<String, List<String>> _selectedSpecFilters = {};

  // Expansion states
  bool _isGenderExpanded = false;
  bool _isBrandExpanded = false;
  bool _isTypeExpanded = false;
  bool _isFitExpanded = false;
  bool _isSizeExpanded = false;
  bool _isColorExpanded = false;
  bool _isPriceExpanded = false;
  final Map<String, bool> _specFieldExpanded = {};

  // Shop categories
  List<String> _shopCategories = [];

  // Controllers for price input
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  final TextEditingController _brandSearchController = TextEditingController();
  List<String> _filteredBrands = [];

  // Available options
  List<String> _availableBrands = [];

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
    _initializeShopData();
    _initializeFilters();
    _initializeAvailableOptions();
  }

  void _initializeShopData() {
    final Map<String, dynamic> shopData =
        widget.shopDoc.data() as Map<String, dynamic>;
    final dynamic categories = shopData['categories'];

    if (categories is List) {
      _shopCategories = categories.cast<String>();
    } else if (categories is String) {
      _shopCategories = [categories];
    }
  }

  void _initializeFilters() {
    _selectedGender = widget.initialGender;
    _selectedBrands = List.from(widget.initialBrands);
    _selectedTypes = List.from(widget.initialTypes);
    _selectedFits = List.from(widget.initialFits);
    _selectedSizes = List.from(widget.initialSizes);
    _selectedColors = List.from(widget.initialColors);
    _minPrice = widget.initialMinPrice;
    _maxPrice = widget.initialMaxPrice;

    _minPriceController.text = _minPrice?.toString() ?? '';
    _maxPriceController.text = _maxPrice?.toString() ?? '';

    if (widget.initialSpecFilters != null) {
      _selectedSpecFilters = widget.initialSpecFilters!.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      );
    }
  }

  void _initializeAvailableOptions() {
    // Use the same approach as ServerSideFilterDataManager
    _availableBrands = globalBrands;
    _filteredBrands = List.from(_availableBrands);
  }

  void _filterBrands(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredBrands = _availableBrands;
      } else {
        _filteredBrands = _availableBrands
            .where((brand) => brand.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  // Helper methods to check filter availability
  bool _shouldShowGenderFilter() {
    // Gender filter should NOT appear for these categories
    const excludedCategories = {
      'Books, Stationery & Hobby',
      'Tools & Hardware',
      'Pet Supplies',
      'Automotive'
    };

    // If shop has any category that's NOT in excluded list, show gender filter
    return _shopCategories
        .any((category) => !excludedCategories.contains(category));
  }

  bool _shouldShowClothingFilters() {
    // Show clothing filters only if shop has Clothing & Fashion category
    return _shopCategories.contains('Clothing & Fashion');
  }

  String getLocalizedColorName(String colorName, AppLocalizations l10n) {
    switch (colorName) {
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
        return colorName;
    }
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
        content: Text(l10n.invalidPriceRange ??
            'Minimum price cannot be greater than maximum price'),
        backgroundColor: Colors.red,
      ),
    );
  }

  int _getTotalSelectedFilters() {
    int count = 0;
    if (_selectedGender != null) count++;
    count += _selectedBrands.length;
    count += _selectedTypes.length;
    count += _selectedFits.length;
    count += _selectedSizes.length;
    count += _selectedColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    for (final vals in _selectedSpecFilters.values) {
      count += vals.length;
    }
    return count;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedGender = null;
      _selectedBrands.clear();
      _selectedTypes.clear();
      _selectedFits.clear();
      _selectedSizes.clear();
      _selectedColors.clear();
      _selectedSpecFilters.clear();
      _minPrice = null;
      _maxPrice = null;
      _minPriceController.clear();
      _maxPriceController.clear();
    });
  }

  Widget _buildPriceChip(String label, double? min, double? max, bool isDark) {
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
          color: isSelected
              ? Colors.orange
              : (isDark ? Colors.grey[700] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.orange
                : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white : Colors.grey[700]),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _brandSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            onPressed: _clearAllFilters,
            child: Text(
              l10n.clear,
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Gender Filter (conditional)
                    if (_shouldShowGenderFilter()) ...[
                      ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.gender ?? 'Gender'),
                            if (_selectedGender != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(
                          _isGenderExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.orange,
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _isGenderExpanded = expanded;
                          });
                        },
                        children: [
                          RadioListTile<String>(
                            title: Text(l10n.clothingGenderWomen ?? 'Women'),
                            value: 'Women',
                            groupValue: _selectedGender,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value;
                              });
                            },
                            activeColor: Colors.orange,
                          ),
                          RadioListTile<String>(
                            title: Text(l10n.clothingGenderMen ?? 'Men'),
                            value: 'Men',
                            groupValue: _selectedGender,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value;
                              });
                            },
                            activeColor: Colors.orange,
                          ),
                          RadioListTile<String>(
                            title: Text(l10n.clothingGenderUnisex ?? 'Unisex'),
                            value: 'Unisex',
                            groupValue: _selectedGender,
                            onChanged: (value) {
                              setState(() {
                                _selectedGender = value;
                              });
                            },
                            activeColor: Colors.orange,
                          ),
                        ],
                      ),
                      Divider(
                        color: Colors.grey[300],
                        thickness: 1,
                        height: 1,
                      ),
                    ],

                    // Brand Filter (always present)
                    if (_availableBrands.isNotEmpty) ...[
                      ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.brand ?? 'Brand'),
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
                          ListTile(
                            title: Text(
                              l10n.clearBrands ?? 'Clear All Brands',
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

                          // Search bar
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: TextField(
                              controller: _brandSearchController,
                              style: TextStyle(
                                  color: isDark ? Colors.white : null),
                              decoration: InputDecoration(
                                hintText: l10n.search ?? 'Search',
                                hintStyle: TextStyle(
                                    color: isDark ? Colors.grey[500] : null),
                                prefixIcon: Icon(Icons.search,
                                    color: isDark ? Colors.grey[400] : null),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.grey[600]!
                                          : Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.grey[600]!
                                          : Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: Colors.orange),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                filled: true,
                                fillColor: isDark ? Colors.grey[800] : null,
                              ),
                              onChanged: _filterBrands,
                            ),
                          ),

                          Divider(
                              height: 1,
                              color: isDark ? Colors.grey[600] : null),

                          // Filtered brand list
                          Container(
                            height: 300,
                            child: ListView.builder(
                              itemCount: _filteredBrands.length,
                              itemBuilder: (context, index) {
                                final brand = _filteredBrands[index];
                                return CheckboxListTile(
                                  title: Text(
                                    brand,
                                    style: TextStyle(
                                        color: isDark ? Colors.white : null),
                                  ),
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
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 0),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      Divider(
                        color: Colors.grey[300],
                        thickness: 1,
                        height: 1,
                      ),
                    ],

                    // Clothing Filters (conditional - only for Clothing & Fashion)
                    if (_shouldShowClothingFilters()) ...[
                      // Type Filter
                      ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.clothingType ?? 'Type'),
                            if (_selectedTypes.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_selectedTypes.length}',
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
                          _isTypeExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.orange,
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _isTypeExpanded = expanded;
                          });
                        },
                        children:
                            AllInOneCategoryData.kClothingTypes.map((type) {
                          final localizedType =
                              AllInOneCategoryData.localizeClothingType(
                                  type, l10n);
                          return CheckboxListTile(
                            title: Text(localizedType),
                            value: _selectedTypes.contains(type),
                            onChanged: (bool? selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedTypes.add(type);
                                } else {
                                  _selectedTypes.remove(type);
                                }
                              });
                            },
                            activeColor: Colors.orange,
                          );
                        }).toList(),
                      ),
                      Divider(
                        color: Colors.grey[300],
                        thickness: 1,
                        height: 1,
                      ),

                      // Fit Filter
                      ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.clothingFit ?? 'Fit'),
                            if (_selectedFits.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_selectedFits.length}',
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
                          _isFitExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.orange,
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _isFitExpanded = expanded;
                          });
                        },
                        children: AllInOneCategoryData.kClothingFits.map((fit) {
                          final localizedFit =
                              AllInOneCategoryData.localizeClothingFit(
                                  fit, l10n);
                          return CheckboxListTile(
                            title: Text(localizedFit),
                            value: _selectedFits.contains(fit),
                            onChanged: (bool? selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedFits.add(fit);
                                } else {
                                  _selectedFits.remove(fit);
                                }
                              });
                            },
                            activeColor: Colors.orange,
                          );
                        }).toList(),
                      ),
                      Divider(
                        color: Colors.grey[300],
                        thickness: 1,
                        height: 1,
                      ),

                      // Size Filter
                      ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.clothingSize ?? 'Size'),
                            if (_selectedSizes.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_selectedSizes.length}',
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
                          _isSizeExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.orange,
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _isSizeExpanded = expanded;
                          });
                        },
                        children:
                            AllInOneCategoryData.kClothingSizes.map((size) {
                          final localizedSize =
                              AllInOneCategoryData.localizeClothingSize(
                                  size, l10n);
                          return CheckboxListTile(
                            title: Text(localizedSize),
                            value: _selectedSizes.contains(size),
                            onChanged: (bool? selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedSizes.add(size);
                                } else {
                                  _selectedSizes.remove(size);
                                }
                              });
                            },
                            activeColor: Colors.orange,
                          );
                        }).toList(),
                      ),
                      Divider(
                        color: Colors.grey[300],
                        thickness: 1,
                        height: 1,
                      ),
                    ],

                    // Color Filter (always present)
                    ExpansionTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.color ?? 'Color'),
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
                          _isColorExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.orange,
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _isColorExpanded = expanded;
                          });
                        },
                        children: [
                          ListTile(
                            title: Text(
                              l10n.clearColors ?? 'Clear All Colors',
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
                          Divider(
                              height: 1,
                              color: isDark ? Colors.grey[600] : null),
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
                                    getLocalizedColorName(name, l10n);
                                final isSelected =
                                    _selectedColors.contains(name);

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
                                          : (isDark
                                              ? Colors.grey[800]
                                              : Colors.grey[100]),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.orange
                                            : (isDark
                                                ? Colors.grey[600]!
                                                : Colors.grey[300]!),
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
                                              width:
                                                  value == Colors.white ? 2 : 1,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            localized,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
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
                          )
                        ]),
                    Divider(
                      color: Colors.grey[300],
                      thickness: 1,
                      height: 1,
                    ),

                    // Price Range Filter (always present)
                    ExpansionTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.priceRange2 ?? 'Price Range'),
                          if (_minPrice != null || _maxPrice != null)
                            const Icon(Icons.check,
                                color: Colors.orange, size: 20),
                        ],
                      ),
                      trailing: Icon(
                        _isPriceExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
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
                                      style: TextStyle(
                                          color: isDark ? Colors.white : null),
                                      decoration: InputDecoration(
                                        labelText: l10n.minPrice ?? 'Min Price',
                                        labelStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[300]
                                                : null),
                                        hintText: '0',
                                        hintStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[500]
                                                : null),
                                        suffixText: 'TL',
                                        suffixStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[300]
                                                : null),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[300]!),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[300]!),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Colors.orange),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        filled: true,
                                        fillColor:
                                            isDark ? Colors.grey[800] : null,
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
                                      style: TextStyle(
                                          color: isDark ? Colors.white : null),
                                      decoration: InputDecoration(
                                        labelText: l10n.maxPrice ?? 'Max Price',
                                        labelStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[300]
                                                : null),
                                        hintText: '∞',
                                        hintStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[500]
                                                : null),
                                        suffixText: 'TL',
                                        suffixStyle: TextStyle(
                                            color: isDark
                                                ? Colors.grey[300]
                                                : null),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[300]!),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide(
                                              color: isDark
                                                  ? Colors.grey[600]!
                                                  : Colors.grey[300]!),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                              color: Colors.orange),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        filled: true,
                                        fillColor:
                                            isDark ? Colors.grey[800] : null,
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
                                l10n.quickPriceRanges ?? 'Quick Price Ranges',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildPriceChip('0 - 100 TL', 0, 100, isDark),
                                  _buildPriceChip(
                                      '100 - 500 TL', 100, 500, isDark),
                                  _buildPriceChip(
                                      '500 - 1000 TL', 500, 1000, isDark),
                                  _buildPriceChip(
                                      '1000+ TL', 1000, null, isDark),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Dynamic Spec Filter Sections (from Typesense facets)
                    ...widget.availableSpecFacets.entries.map((specEntry) {
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
                          Divider(
                            color: Colors.grey[300],
                            thickness: 1,
                            height: 1,
                          ),
                          ExpansionTile(
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(sectionTitle),
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
                              ListTile(
                                title: Text(
                                  l10n.clear,
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
                              Container(
                                height: facetValues.length > 8 ? 300 : null,
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
                                      title: Text('$localizedName ($count)'),
                                      value: selectedForField.contains(value),
                                      onChanged: (selected) {
                                        setState(() {
                                          final list =
                                              _selectedSpecFilters[fieldName] ??=
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
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 0),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }),
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
                    if (!_validatePriceRange()) {
                      _showPriceError(l10n);
                      return;
                    }

                    final totalFilters = _getTotalSelectedFilters();
                    Navigator.pop(context, {
                      'gender': _selectedGender,
                      'brands': _selectedBrands,
                      'types': _selectedTypes,
                      'fits': _selectedFits,
                      'sizes': _selectedSizes,
                      'colors': _selectedColors,
                      'minPrice': _minPrice,
                      'maxPrice': _maxPrice,
                      'totalFilters': totalFilters,
                      'specFilters': _selectedSpecFilters,
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
                    '${l10n.apply} (${_getTotalSelectedFilters()})',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
