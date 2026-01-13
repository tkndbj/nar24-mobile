import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import 'package:go_router/go_router.dart';

class ListCategoryScreen extends StatefulWidget {
  final String? initialCategory;
  final String? initialSubcategory;
  final String? initialSubSubcategory;

  const ListCategoryScreen({
    Key? key,
    this.initialCategory,
    this.initialSubcategory,
    this.initialSubSubcategory,
  }) : super(key: key);

  @override
  _ListCategoryScreenState createState() => _ListCategoryScreenState();
}

class _ListCategoryScreenState extends State<ListCategoryScreen> {
  String? _selectedCategory;
  String? _selectedSubcategory;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchFocused = false;
  List<Map<String, String>> _searchResults = [];
  final FocusNode _searchFocusNode = FocusNode();
  Set<String> _expandedSubcategories = {};

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ??
        (AllInOneCategoryData.kCategories.isNotEmpty
            ? AllInOneCategoryData.kCategories[0]['key']
            : null);
    _selectedSubcategory = widget.initialSubcategory;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    List<Map<String, String>> results = [];
    for (var category in AllInOneCategoryData.kCategories) {
      String catKey = category['key']!;
      String localizedCat = AllInOneCategoryData.localizeCategoryKey(
              catKey, AppLocalizations.of(context))
          .toLowerCase();
      if (localizedCat.contains(query)) {
        results.add({
          'category': catKey,
          'subcategory': '',
          'subsubcategory': '',
          'display': localizedCat
        });
      }

      var subcategories = AllInOneCategoryData.kSubcategories[catKey] ?? [];
      for (var sub in subcategories) {
        String localizedSub = AllInOneCategoryData.localizeSubcategoryKey(
                catKey, sub, AppLocalizations.of(context))
            .toLowerCase();
        if (localizedSub.contains(query)) {
          results.add({
            'category': catKey,
            'subcategory': sub,
            'subsubcategory': '',
            'display': '$localizedCat > $localizedSub'
          });
        }

        // Search in subsubcategories
        var subsubcategories =
            AllInOneCategoryData.kSubSubcategories[catKey]?[sub] ?? [];
        for (var subsub in subsubcategories) {
          String localizedSubSub =
              AllInOneCategoryData.localizeSubSubcategoryKey(
                      catKey, sub, subsub, AppLocalizations.of(context))
                  .toLowerCase();
          if (localizedSubSub.contains(query)) {
            results.add({
              'category': catKey,
              'subcategory': sub,
              'subsubcategory': subsub,
              'display': '$localizedCat > $localizedSub > $localizedSubSub'
            });
          }
        }
      }
    }
    setState(() {
      _searchResults = results;
    });
  }

  // FIXED: Simply return the category/subcategory/subsubcategory selection
  // Let ListProductScreen handle the dynamic flow execution
  void _handleCategorySelection(
    String category,
    String subcategory,
    String subsubcategory,
  ) {
    context.pop({
      'category': category,
      'subcategory': subcategory,
      'subsubcategory': subsubcategory,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rawCategories =
        AllInOneCategoryData.kCategories.map((map) => map['key']!).toList();
    final localizedCategories = rawCategories
        .map((key) => AllInOneCategoryData.localizeCategoryKey(key, l10n))
        .toList();

    final rawSubcategories = _selectedCategory != null
        ? AllInOneCategoryData.kSubcategories[_selectedCategory!] ?? []
        : [];
    final localizedSubcategories = rawSubcategories
        .map((sub) => AllInOneCategoryData.localizeSubcategoryKey(
            _selectedCategory!, sub, l10n))
        .toList();

    final rawSubSubcategories =
        _selectedCategory != null && _selectedSubcategory != null
            ? (AllInOneCategoryData.kSubSubcategories[_selectedCategory!]
                    ?[_selectedSubcategory!] ??
                [])
            : [];
    final localizedSubSubcategories = rawSubSubcategories
        .map((subsub) => AllInOneCategoryData.localizeSubSubcategoryKey(
            _selectedCategory!, _selectedSubcategory!, subsub, l10n))
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isSearchFocused) {
              setState(() {
                _isSearchFocused = false;
                _searchController.clear();
                _searchFocusNode.unfocus();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          l10n.selectCategory,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onTap: () {
                setState(() {
                  _isSearchFocused = true;
                });
              },
              onSubmitted: (_) {
                setState(() {
                  _isSearchFocused = false;
                });
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1C1A29)
                    : Colors.grey[100],
                hintText: l10n.searchCategory,
                hintStyle: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Color(0xFF00A86B),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Colors.grey[100]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Colors.grey[100]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(
                    color: Colors.grey[100]!,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
            ),
          ),
          Expanded(
            child: _isSearchFocused && _searchController.text.isNotEmpty
                ? ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      return ListTile(
                        title: Text(result['display']!),
                        onTap: () {
                          final cat = result['category']!;
                          final sub = result['subcategory']!;
                          final subsub = result['subsubcategory']!;

                          // FIXED: Always use the simplified handler
                          if (subsub.isNotEmpty) {
                            _handleCategorySelection(cat, sub, subsub);
                          } else if (sub.isNotEmpty) {
                            setState(() {
                              _selectedCategory = cat;
                              _selectedSubcategory = sub;
                              _isSearchFocused = false;
                              _searchController.clear();
                            });
                          } else {
                            setState(() {
                              _selectedCategory = cat;
                              _selectedSubcategory = null;
                              _isSearchFocused = false;
                              _searchController.clear();
                            });
                          }
                        },
                      );
                    },
                  )
                : _isSearchFocused
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Use fixed width on tablets, percentage on mobile
                          final isTablet = constraints.maxWidth >= 600;
                          final categoryColumnWidth = isTablet ? 100.0 : constraints.maxWidth * 0.25;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category list
                              Container(
                                width: categoryColumnWidth,
                            color:
                                Theme.of(context).brightness == Brightness.light
                                    ? Colors.grey[50]
                                    : const Color.fromARGB(255, 33, 31, 49),
                            child: ListView.builder(
                              itemCount: localizedCategories.length,
                              itemBuilder: (ctx, i) {
                                final raw = rawCategories[i];
                                final loc = localizedCategories[i];
                                final sel = raw == _selectedCategory;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  title: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(_getIconForCategory(raw),
                                          color: sel
                                              ? Colors.orange
                                              : Colors.grey[500],
                                          size: 20),
                                      const SizedBox(height: 4),
                                      Text(loc,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: sel
                                                ? Colors.orange
                                                : Theme.of(context)
                                                            .brightness ==
                                                        Brightness.light
                                                    ? Colors.grey[600]
                                                    : Colors.white,
                                          )),
                                    ],
                                  ),
                                  tileColor: sel
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.1)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedCategory = raw;
                                      _selectedSubcategory = null;
                                    });
                                  },
                                );
                              },
                            ),
                          ),

                          // Subcategory + sub-subcategories
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selectedCategory != null)
                                    ...localizedSubcategories
                                        .asMap()
                                        .entries
                                        .map((e) {
                                      final idx = e.key;
                                      final loc = e.value;
                                      final rawSubcategory =
                                          rawSubcategories[idx];

                                      final rawSubSub = AllInOneCategoryData
                                                      .kSubSubcategories[
                                                  _selectedCategory!]
                                              ?[rawSubcategory] ??
                                          [];
                                      final localizedSubSub = rawSubSub
                                          .map((ss) => AllInOneCategoryData
                                              .localizeSubSubcategoryKey(
                                                  _selectedCategory!,
                                                  rawSubcategory,
                                                  ss,
                                                  l10n))
                                          .toList();

                                      return Column(
                                        children: [
                                          ExpansionTile(
                                            title: Text(
                                              loc,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: _expandedSubcategories
                                                        .contains(
                                                            rawSubcategory)
                                                    ? Colors.orange
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurface,
                                              ),
                                            ),
                                            tilePadding:
                                                const EdgeInsets.only(left: 8),
                                            onExpansionChanged: (expanded) {
                                              setState(() {
                                                if (expanded) {
                                                  _expandedSubcategories
                                                      .add(rawSubcategory);
                                                } else {
                                                  _expandedSubcategories
                                                      .remove(rawSubcategory);
                                                }
                                              });
                                            },
                                            children: localizedSubSub
                                                .asMap()
                                                .entries
                                                .map((subSubEntry) {
                                              final subSubIdx = subSubEntry.key;
                                              final subSubLoc =
                                                  subSubEntry.value;
                                              return Column(
                                                children: [
                                                  ListTile(
                                                    contentPadding:
                                                        const EdgeInsets.only(
                                                            left: 32),
                                                    title: Text(
                                                      subSubLoc,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                      ),
                                                    ),
                                                    onTap: () {
                                                      // FIXED: Use simplified handler
                                                      _handleCategorySelection(
                                                        _selectedCategory!,
                                                        rawSubcategory,
                                                        rawSubSub[subSubIdx],
                                                      );
                                                    },
                                                  ),
                                                  if (subSubIdx <
                                                      localizedSubSub.length -
                                                          1)
                                                    const Divider(
                                                      height: 1,
                                                      thickness: 0.5,
                                                      color: Color.fromARGB(
                                                          255, 230, 230, 230),
                                                    ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                ],
                              ),
                            ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForCategory(String categoryKey) {
    switch (categoryKey) {
      case 'Clothing & Fashion':
        return FeatherIcons.user;
      case 'Footwear':
        return FeatherIcons.shoppingBag; // or could use a shoe-specific icon
      case 'Accessories':
        return FeatherIcons.watch;
      case 'Mother & Child':
        return FeatherIcons.heart;
      case 'Home & Furniture':
        return FeatherIcons.home;
      case 'Beauty & Personal Care':
        return FeatherIcons.droplet; // or FeatherIcons.star for beauty
      case 'Bags & Luggage':
        return FeatherIcons.briefcase;
      case 'Electronics':
        return FeatherIcons.smartphone;
      case 'Sports & Outdoor':
        return FeatherIcons.activity;
      case 'Books, Stationery & Hobby':
        return FeatherIcons.book;
      case 'Tools & Hardware':
        return FeatherIcons.settings;
      case 'Pet Supplies':
        return FeatherIcons
            .heart; // or could use a pet-specific icon if available
      case 'Automotive':
        return FeatherIcons.truck;
      case 'Health & Wellness':
        return FeatherIcons.shield; // or FeatherIcons.heart for wellness
      default:
        return FeatherIcons.grid;
    }
  }
}
