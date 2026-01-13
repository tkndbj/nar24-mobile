import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import 'package:go_router/go_router.dart';

class ListClothingDetailsScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListClothingDetailsScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListClothingDetailsScreenState createState() =>
      _ListClothingDetailsScreenState();
}

class _ListClothingDetailsScreenState extends State<ListClothingDetailsScreen> {
  List<String> _selectedSizes = [];
  String? _selectedFit;
  List<String> _selectedTypes = [];

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedSizes =
          List<String>.from(widget.initialAttributes!['clothingSizes'] ?? []);
      _selectedFit = widget.initialAttributes!['clothingFit'] as String?;
      if (widget.initialAttributes!['clothingTypes'] != null) {
  _selectedTypes = List<String>.from(widget.initialAttributes!['clothingTypes']);
} else if (widget.initialAttributes!['clothingType'] != null) {
  // Backward compatibility: convert single value to array
  _selectedTypes = [widget.initialAttributes!['clothingType'] as String];
}
    }
  }

  void _saveClothingDetails() {
    if (_selectedSizes.isEmpty || _selectedFit == null || _selectedTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).pleaseSelectAllClothingDetails)),
      );
      return;
    }

    // Return the clothing details as dynamic attributes
    final result = <String, dynamic>{
      'clothingSizes': _selectedSizes,
      'clothingFit': _selectedFit,
      'clothingTypes': _selectedTypes.toList(),
    };

    // Include any existing attributes that were passed in
    if (widget.initialAttributes != null) {
      widget.initialAttributes!.forEach((key, value) {
       if (!result.containsKey(key) && key != 'clothingType') {
  result[key] = value;
}
      });
    }

    context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.clothingDetails,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          // dynamic background: dark mode vs light mode
          color: isDark
              ? const Color.fromARGB(255, 33, 31, 49)
              : const Color(0xFFF5F5F5),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Clothing Size Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l10n.clothingSize,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ...AllInOneCategoryData.kClothingSizes.map((size) {
                  final localizedSize =
                      AllInOneCategoryData.localizeClothingSize(size, l10n);
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: isDark
                            ? const Color.fromARGB(
                                255, 45, 43, 60) // dark‐mode row background
                            : Colors.white,
                        child: CheckboxListTile(
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
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFF00A86B),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                      ),
                    ],
                  );
                }).toList(),
                const SizedBox(height: 16),

                // Clothing Fit Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l10n.clothingFit,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ...AllInOneCategoryData.kClothingFits.map((fit) {
                  final localizedFit =
                      AllInOneCategoryData.localizeClothingFit(fit, l10n);
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: isDark
                            ? const Color.fromARGB(
                                255, 45, 43, 60) // dark‐mode row background
                            : Colors.white,
                        child: RadioListTile<String>(
                          title: Text(localizedFit),
                          value: fit,
                          groupValue: _selectedFit,
                          onChanged: (value) {
                            setState(() {
                              _selectedFit = value;
                            });
                          },
                          activeColor: const Color(0xFF00A86B),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                      ),
                    ],
                  );
                }).toList(),
                const SizedBox(height: 16),

                // Clothing Type Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    l10n.clothingType,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ...AllInOneCategoryData.kClothingTypes.map((type) {
                  final localizedType =
                      AllInOneCategoryData.localizeClothingType(type, l10n);
                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: isDark
                            ? const Color.fromARGB(
                                255, 45, 43, 60) // dark‐mode row background
                            : Colors.white,
                        child: CheckboxListTile(
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
  controlAffinity: ListTileControlAffinity.leading,
  activeColor: const Color(0xFF00A86B),
),
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                      ),
                    ],
                  );
                }).toList(),
                const SizedBox(height: 24),

                // Save Button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveClothingDetails,
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
      ),
    );
  }
}
