import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/brands.dart';
import '../../utils/color_localization.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../models/dynamic_filter.dart';

// Server-side data manager for metadata only
class ServerSideFilterDataManager {
  static ServerSideFilterDataManager? _instance;
  static ServerSideFilterDataManager get instance =>
      _instance ??= ServerSideFilterDataManager._();
  ServerSideFilterDataManager._();

  // Cached static data
  List<String>? _cachedBrands;
  List<String>? _cachedCategories;
  Map<String, List<String>>? _cachedSubcategories;
  Map<String, Map<String, List<String>>>? _cachedSubSubcategories;

  // Get all brands from constants (static data)
  List<String> getAllBrands() {
    if (_cachedBrands != null) return _cachedBrands!;

    final allBrands = <String>{};
    try {
      allBrands.addAll(globalBrands.cast<String>());
    } catch (e) {
      debugPrint('Error loading brands from constants: $e');
    }

    _cachedBrands = allBrands.toList()..sort();
    return _cachedBrands!;
  }

  // Get all categories from constants (static data)
  Map<String, dynamic> getAllCategoriesData() {
    if (_cachedCategories != null &&
        _cachedSubcategories != null &&
        _cachedSubSubcategories != null) {
      return {
        'categories': _cachedCategories!,
        'subcategories': _cachedSubcategories!,
        'subSubcategories': _cachedSubSubcategories!,
      };
    }

    try {
      final categories =
          AllInOneCategoryData.kCategories.map((cat) => cat['key']!).toList();

      final subcategories = <String, List<String>>{};
      for (final category in categories) {
        final categorySubcats = AllInOneCategoryData.kSubcategories[category];
        if (categorySubcats != null) {
          subcategories[category] = List<String>.from(categorySubcats);
        }
      }

      final subSubcategories = <String, Map<String, List<String>>>{};
      for (final category in categories) {
        final categoryData = AllInOneCategoryData.kSubSubcategories[category];
        if (categoryData != null) {
          subSubcategories[category] = {};
          for (final subcategory in categoryData.keys) {
            final subSubcatList = categoryData[subcategory];
            if (subSubcatList != null) {
              subSubcategories[category]![subcategory] =
                  List<String>.from(subSubcatList);
            }
          }
        }
      }

      _cachedCategories = categories;
      _cachedSubcategories = subcategories;
      _cachedSubSubcategories = subSubcategories;

      return {
        'categories': _cachedCategories!,
        'subcategories': _cachedSubcategories!,
        'subSubcategories': _cachedSubSubcategories!,
      };
    } catch (e) {
      debugPrint('Error loading categories data: $e');
      return {
        'categories': <String>[],
        'subcategories': <String, List<String>>{},
        'subSubcategories': <String, Map<String, List<String>>>{},
      };
    }
  }

  // Optional: Get dynamic brands/categories from server for enhanced experience
  Future<List<String>> getServerBrands(DynamicFilter baseFilter) async {
    try {
      final query = FirebaseFirestore.instance
          .collection(baseFilter.collection ?? 'shop_products');

      // Use aggregation query for better performance
      final snapshot = await query.limit(1000).get();
      final brands = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final brand = data['brandModel'] as String?;
        if (brand != null && brand.isNotEmpty) {
          brands.add(brand);
        }
      }

      // Merge with static brands
      final allBrands = {...getAllBrands(), ...brands};
      return allBrands.toList()..sort();
    } catch (e) {
      debugPrint('Error fetching server brands: $e');
      return getAllBrands();
    }
  }

  void clearCache() {
    _cachedBrands = null;
    _cachedCategories = null;
    _cachedSubcategories = null;
    _cachedSubSubcategories = null;
  }
}

// Optimized UI widgets
class OptimizedBrandList extends StatefulWidget {
  final List<String> brands;
  final List<String> selectedBrands;
  final Function(String, bool) onBrandChanged;
  final AppLocalizations l10n;

  const OptimizedBrandList({
    Key? key,
    required this.brands,
    required this.selectedBrands,
    required this.onBrandChanged,
    required this.l10n,
  }) : super(key: key);

  @override
  State<OptimizedBrandList> createState() => _OptimizedBrandListState();
}

class _OptimizedBrandListState extends State<OptimizedBrandList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.brands.length,
      itemBuilder: (context, index) {
        final brand = widget.brands[index];
        return CheckboxListTile(
          title: Text(brand),
          value: widget.selectedBrands.contains(brand),
          onChanged: (selected) =>
              widget.onBrandChanged(brand, selected ?? false),
          activeColor: Colors.orange,
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        );
      },
    );
  }
}

class MarketScreenDynamicFiltersFilterScreen extends StatefulWidget {
  final DynamicFilter baseFilter;
  final List<String>? initialBrands;
  final List<String>? initialColors;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final String? initialCategory;
  final String? initialSubcategory;
  final String? initialSubSubcategory;

  const MarketScreenDynamicFiltersFilterScreen({
    Key? key,
    required this.baseFilter,
    this.initialBrands,
    this.initialColors,
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialCategory,
    this.initialSubcategory,
    this.initialSubSubcategory,
  }) : super(key: key);

  @override
  _MarketScreenDynamicFiltersFilterScreenState createState() =>
      _MarketScreenDynamicFiltersFilterScreenState();
}

class _MarketScreenDynamicFiltersFilterScreenState
    extends State<MarketScreenDynamicFiltersFilterScreen> {
  // Filter state
  List<String> _selectedBrands = [];
  List<String> _selectedColors = [];
  double? _minPrice;
  double? _maxPrice;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String? _selectedSubSubcategory;

  // Available options - loaded immediately
  List<String> _availableBrands = [];
  List<String> _availableCategories = [];
  Map<String, List<String>> _availableSubcategories = {};
  Map<String, Map<String, List<String>>> _availableSubSubcategories = {};

  // UI state
  bool _isBrandExpanded = false;
  bool _isColorExpanded = false;
  bool _isPriceExpanded = false;
  bool _isCategoryExpanded = false;
  bool _isEnhancing = false;

  // Controllers
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  TextEditingController _brandSearchController = TextEditingController();
  List<String> _filteredBrands = [];

  // Static color options
  static const List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blue', 'color': Colors.blue},
    {'name': 'Orange', 'color': Colors.orange},
    {'name': 'Yellow', 'color': Colors.yellow},
    {'name': 'Black', 'color': Colors.black},
    {'name': 'Brown', 'color': Colors.brown},
    {'name': 'Dark Blue', 'color': Color(0xFF00008B)},
    {'name': 'Gray', 'color': Colors.grey},
    {'name': 'Pink', 'color': Colors.pink},
    {'name': 'Red', 'color': Colors.red},
    {'name': 'White', 'color': Colors.white},
    {'name': 'Green', 'color': Colors.green},
    {'name': 'Purple', 'color': Colors.purple},
    {'name': 'Teal', 'color': Colors.teal},
    {'name': 'Lime', 'color': Colors.lime},
    {'name': 'Cyan', 'color': Colors.cyan},
    {'name': 'Magenta', 'color': Color(0xFFFF00FF)},
    {'name': 'Indigo', 'color': Colors.indigo},
    {'name': 'Amber', 'color': Colors.amber},
    {'name': 'Deep Orange', 'color': Colors.deepOrange},
    {'name': 'Light Blue', 'color': Colors.lightBlue},
    {'name': 'Deep Purple', 'color': Colors.deepPurple},
    {'name': 'Light Green', 'color': Colors.lightGreen},
    {'name': 'Dark Gray', 'color': Color(0xFF444444)},
    {'name': 'Beige', 'color': Color(0xFFF5F5DC)},
    {'name': 'Turquoise', 'color': Color(0xFF40E0D0)},
    {'name': 'Violet', 'color': Color(0xFFEE82EE)},
    {'name': 'Olive', 'color': Color(0xFF808000)},
    {'name': 'Maroon', 'color': Color(0xFF800000)},
    {'name': 'Navy', 'color': Color(0xFF000080)},
    {'name': 'Silver', 'color': Color(0xFFC0C0C0)},
  ];

  @override
  void initState() {
    super.initState();
    _initializeFilters();
    _loadAvailableDataImmediate();
    _enhanceDataInBackground();
  }

  void _initializeFilters() {
    _selectedBrands = widget.initialBrands != null
        ? List.from(widget.initialBrands!)
        : <String>[];
    _selectedColors = widget.initialColors != null
        ? List.from(widget.initialColors!)
        : <String>[];
    _minPrice = widget.initialMinPrice;
    _maxPrice = widget.initialMaxPrice;
    _selectedCategory = widget.initialCategory;
    _selectedSubcategory = widget.initialSubcategory;
    _selectedSubSubcategory = widget.initialSubSubcategory;

    _minPriceController.text = _minPrice?.toString() ?? '';
    _maxPriceController.text = _maxPrice?.toString() ?? '';
  }

  void _loadAvailableDataImmediate() {
    try {
      _availableBrands = ServerSideFilterDataManager.instance.getAllBrands();

      final categoriesData =
          ServerSideFilterDataManager.instance.getAllCategoriesData();
      _availableCategories = categoriesData['categories'] as List<String>;
      _availableSubcategories =
          categoriesData['subcategories'] as Map<String, List<String>>;
      _availableSubSubcategories = categoriesData['subSubcategories']
          as Map<String, Map<String, List<String>>>;

      _filteredBrands = List.from(_availableBrands);

      setState(() {});
    } catch (e) {
      debugPrint('Error loading immediate data: $e');
    }
  }

  void _enhanceDataInBackground() async {
    setState(() {
      _isEnhancing = true;
    });

    try {
      final enhancedBrands = await ServerSideFilterDataManager.instance
          .getServerBrands(widget.baseFilter);

      if (mounted) {
        setState(() {
          _availableBrands = enhancedBrands;
          _filteredBrands = List.from(_availableBrands);
          _isEnhancing = false;
        });
      }
    } catch (e) {
      debugPrint('Error enhancing data: $e');
      if (mounted) {
        setState(() {
          _isEnhancing = false;
        });
      }
    }
  }

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

  int _getTotalSelected() {
    int count = 0;
    count += _selectedBrands.length;
    count += _selectedColors.length;
    if (_minPrice != null || _maxPrice != null) count++;
    if (_selectedCategory != null) count++;
    if (_selectedSubcategory != null) count++;
    if (_selectedSubSubcategory != null) count++;
    return count;
  }

  void _clearAllFilters() {
    setState(() {
      _selectedBrands.clear();
      _selectedColors.clear();
      _minPrice = null;
      _maxPrice = null;
      _selectedCategory = null;
      _selectedSubcategory = null;
      _selectedSubSubcategory = null;
      _minPriceController.clear();
      _maxPriceController.clear();
    });
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
        content: Text(
          _getSafeLocalizedString(() => l10n.invalidPriceRange,
              'Minimum price cannot be greater than maximum price'),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  List<String> _getSubcategoriesForCategory(String category) {
    return _availableSubcategories[category] ?? [];
  }

  List<String> _getSubSubcategoriesForSubcategory(
      String category, String subcategory) {
    return _availableSubSubcategories[category]?[subcategory] ?? [];
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : null,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1C1A29)
            : Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : null),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _getSafeLocalizedString(() => l10n.filter, 'Filter'),
          style: TextStyle(color: isDark ? Colors.white : null),
        ),
        actions: [
          if (_isEnhancing)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
            ),
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
                  _buildCategoryFilter(l10n, isDark),
                  if (_availableBrands.isNotEmpty)
                    _buildBrandFilter(l10n, isDark),
                  _buildColorFilter(l10n, isDark),
                  _buildPriceFilter(l10n, isDark),
                ],
              ),
            ),
          ),
          _buildApplyButton(l10n),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(AppLocalizations l10n, bool isDark) {
    return ExpansionTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _getSafeLocalizedString(() => l10n.category, 'Category'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (_selectedCategory != null ||
              _selectedSubcategory != null ||
              _selectedSubSubcategory != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      iconColor: isDark ? Colors.white : null,
      collapsedIconColor: isDark ? Colors.white : null,
      trailing: Icon(
        _isCategoryExpanded ? Icons.expand_less : Icons.expand_more,
        color: Colors.orange,
      ),
      onExpansionChanged: (expanded) {
        setState(() {
          _isCategoryExpanded = expanded;
        });
      },
      children: [
        ListTile(
          title: Text(
            _getSafeLocalizedString(() => l10n.clear, 'Clear Category'),
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.orange,
            ),
          ),
          onTap: () {
            setState(() {
              _selectedCategory = null;
              _selectedSubcategory = null;
              _selectedSubSubcategory = null;
            });
          },
          trailing: (_selectedCategory != null ||
                  _selectedSubcategory != null ||
                  _selectedSubSubcategory != null)
              ? const Icon(Icons.clear, color: Colors.orange)
              : null,
        ),
        Divider(height: 1, color: isDark ? Colors.grey[600] : null),
        ..._availableCategories.map((category) {
          return RadioListTile<String>(
            title: Text(
              AllInOneCategoryData.localizeCategoryKey(category, l10n),
              style: TextStyle(color: isDark ? Colors.white : null),
            ),
            value: category,
            groupValue: _selectedCategory,
            onChanged: (value) {
              setState(() {
                _selectedCategory = value;
                _selectedSubcategory = null;
                _selectedSubSubcategory = null;
              });
            },
            activeColor: Colors.orange,
          );
        }).toList(),
        if (_selectedCategory != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              _getSafeLocalizedString(() => l10n.subcategory, 'Subcategory'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
          ),
          ..._getSubcategoriesForCategory(_selectedCategory!)
              .map((subcategory) {
            return Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: RadioListTile<String>(
                title: Text(
                  AllInOneCategoryData.localizeSubcategoryKey(
                      _selectedCategory!, subcategory, l10n),
                  style: TextStyle(color: isDark ? Colors.white : null),
                ),
                value: subcategory,
                groupValue: _selectedSubcategory,
                onChanged: (value) {
                  setState(() {
                    _selectedSubcategory = value;
                    _selectedSubSubcategory = null;
                  });
                },
                activeColor: Colors.orange,
              ),
            );
          }).toList(),
        ],
        if (_selectedCategory != null && _selectedSubcategory != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 32.0),
            child: Text(
              l10n.subSubcategory,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.grey[600],
              ),
            ),
          ),
          ..._getSubSubcategoriesForSubcategory(
                  _selectedCategory!, _selectedSubcategory!)
              .map((subSubcategory) {
            return Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: RadioListTile<String>(
                title: Text(
                  AllInOneCategoryData.localizeSubSubcategoryKey(
                      _selectedCategory!,
                      _selectedSubcategory!,
                      subSubcategory,
                      l10n),
                  style: TextStyle(color: isDark ? Colors.white : null),
                ),
                value: subSubcategory,
                groupValue: _selectedSubSubcategory,
                onChanged: (value) {
                  setState(() {
                    _selectedSubSubcategory = value;
                  });
                },
                activeColor: Colors.orange,
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildBrandFilter(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.grey[600] : Colors.grey[300]),
        ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getSafeLocalizedString(() => l10n.brand, 'Brand'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : null,
                ),
              ),
              if (_selectedBrands.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          iconColor: isDark ? Colors.white : null,
          collapsedIconColor: isDark ? Colors.white : null,
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

            // ADD SEARCH BAR:
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _brandSearchController,
                style: TextStyle(color: isDark ? Colors.white : null),
                decoration: InputDecoration(
                  hintText:
                      _getSafeLocalizedString(() => l10n.search, 'Search'),
                  hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                  prefixIcon: Icon(Icons.search,
                      color: isDark ? Colors.grey[400] : null),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.orange),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: isDark ? Colors.grey[800] : null,
                ),
                onChanged: _filterBrands,
              ),
            ),

            Divider(height: 1, color: isDark ? Colors.grey[600] : null),

            // REPLACE OptimizedBrandList with filtered version:
            Container(
              height: 300,
              child: ListView.builder(
                itemCount: _filteredBrands.length,
                itemBuilder: (context, index) {
                  final brand = _filteredBrands[index];
                  return CheckboxListTile(
                    title: Text(
                      brand,
                      style: TextStyle(color: isDark ? Colors.white : null),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorFilter(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.grey[600] : Colors.grey[300]),
        ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getSafeLocalizedString(() => l10n.color, 'Color'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : null,
                ),
              ),
              if (_selectedColors.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          iconColor: isDark ? Colors.white : null,
          collapsedIconColor: isDark ? Colors.white : null,
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
            Divider(height: 1, color: isDark ? Colors.grey[600] : null),
            Container(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                            : (isDark ? Colors.grey[800] : Colors.grey[100]),
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
                                color: isDark ? Colors.white : Colors.black,
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
    );
  }

  Widget _buildPriceFilter(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        Divider(
            height: 1,
            thickness: 1,
            color: isDark ? Colors.grey[600] : Colors.grey[300]),
        ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getSafeLocalizedString(() => l10n.priceRange2, 'Price Range'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : null,
                ),
              ),
              if (_minPrice != null || _maxPrice != null)
                const Icon(Icons.check, color: Colors.orange, size: 20),
            ],
          ),
          iconColor: isDark ? Colors.white : null,
          collapsedIconColor: isDark ? Colors.white : null,
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
                          style: TextStyle(color: isDark ? Colors.white : null),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*')),
                          ],
                          decoration: InputDecoration(
                            labelText: _getSafeLocalizedString(
                                () => l10n.minPrice, 'Min Price'),
                            labelStyle: TextStyle(
                                color: isDark ? Colors.grey[300] : null),
                            hintText: '0',
                            hintStyle: TextStyle(
                                color: isDark ? Colors.grey[500] : null),
                            suffixText: 'TL',
                            suffixStyle: TextStyle(
                                color: isDark ? Colors.grey[300] : null),
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
                          onChanged: (_) => _updatePriceFromController(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: isDark ? Colors.white : null),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*')),
                          ],
                          decoration: InputDecoration(
                            labelText: _getSafeLocalizedString(
                                () => l10n.maxPrice, 'Max Price'),
                            labelStyle: TextStyle(
                                color: isDark ? Colors.grey[300] : null),
                            hintText: '∞',
                            hintStyle: TextStyle(
                                color: isDark ? Colors.grey[500] : null),
                            suffixText: 'TL',
                            suffixStyle: TextStyle(
                                color: isDark ? Colors.grey[300] : null),
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
                          onChanged: (_) => _updatePriceFromController(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Quick price buttons
                  Text(
                    _getSafeLocalizedString(
                        () => l10n.quickPriceRanges, 'Quick Price Ranges'),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPriceChip('0 - 100 TL', 0, 100, isDark),
                      _buildPriceChip('100 - 500 TL', 100, 500, isDark),
                      _buildPriceChip('500 - 1000 TL', 500, 1000, isDark),
                      _buildPriceChip('1000+ TL', 1000, null, isDark),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
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

  Widget _buildApplyButton(AppLocalizations l10n) {
    return Container(
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
                'minPrice': _minPrice,
                'maxPrice': _maxPrice,
                'category': _selectedCategory,
                'subcategory': _selectedSubcategory,
                'subSubcategory': _selectedSubSubcategory,
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
    );
  }
}
