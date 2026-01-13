import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductFootwearSizeScreen extends StatefulWidget {
  final String category;
  final String subcategory;
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductFootwearSizeScreen({
    Key? key,
    required this.category,
    required this.subcategory,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductFootwearSizeScreenState createState() =>
      _ListProductFootwearSizeScreenState();
}

class _ListProductFootwearSizeScreenState
    extends State<ListProductFootwearSizeScreen> {
  List<String> _selectedSizes = [];
  final List<String> _womenSizes = [
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43'
  ];
  final List<String> _menSizes = [
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48'
  ];
  final List<String> _kidsSizes = [
    '28',
    '29',
    '30',
    '31',
    '32',
    '33',
    '34',
    '35',
    '36'
  ];
  final List<String> _allSizes = [
    '35',
    '36',
    '37',
    '38',
    '39',
    '40',
    '41',
    '42',
    '43',
    '44',
    '45',
    '46',
    '47',
    '48'
  ];

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedSizes =
          List<String>.from(widget.initialAttributes!['footwearSizes'] ?? []);
    }
  }

  List<String> _getAvailableSizes() {
    if ((widget.category == 'Women' && widget.subcategory == 'Footwear') ||
        (widget.category == 'Shoes & Bags' &&
            widget.subcategory == "Women's Shoes")) {
      return _womenSizes;
    } else if ((widget.category == 'Men' && widget.subcategory == 'Footwear') ||
        (widget.category == 'Shoes & Bags' &&
            widget.subcategory == "Men's Shoes")) {
      return _menSizes;
    } else if (widget.category == 'Shoes & Bags' &&
        widget.subcategory == "Kids' Shoes") {
      return _kidsSizes;
    } else if (widget.category == 'Shoes & Bags' &&
        widget.subcategory == 'Sports Shoes') {
      return _allSizes;
    }
    return _allSizes; // default
  }

  void _saveFootwearSizes() {
    if (_selectedSizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).pleaseSelectAtLeastOneSize),
        ),
      );
      return;
    }

    // Return the footwear sizes as dynamic attributes
    final result = <String, dynamic>{
      'footwearSizes': _selectedSizes,
    };

    // Include any existing attributes that were passed in
    if (widget.initialAttributes != null) {
      widget.initialAttributes!.forEach((key, value) {
        if (!result.containsKey(key)) {
          result[key] = value;
        }
      });
    }

    context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final availableSizes = _getAvailableSizes();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectSize,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          // dynamic background for light/dark modes
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color.fromARGB(255, 33, 31, 49)
              : const Color(0xFFF5F5F5),
          child: Column(
            children: [
              // scrollable list of sizes
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.selectAvailableSizes,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...availableSizes.map((size) {
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: CheckboxListTile(
                                title: Text(
                                  size,
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
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
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                activeColor: const Color(0xFF00A86B),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[700]
                                  : Colors.grey[300],
                            ),
                          ],
                        );
                      }).toList(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // pinned Save button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveFootwearSizes,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                    ),
                    child: Text(
                      l10n.save,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
