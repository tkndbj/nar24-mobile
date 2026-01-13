// lib/screens/list_product_pant_details.dart

import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import 'package:go_router/go_router.dart';

class ListProductPantDetailsScreen extends StatefulWidget {
  final String category;
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductPantDetailsScreen({
    Key? key,
    required this.category,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductPantDetailsScreenState createState() =>
      _ListProductPantDetailsScreenState();
}

class _ListProductPantDetailsScreenState
    extends State<ListProductPantDetailsScreen> {
  static const int _maxFabricTypes = 4;

  static const List<String> _womenSizes = [
    'XXS / 32',
    'XS / 34',
    'S / 36',
    'M / 38',
    'L / 40',
    'XL / 42',
    'XXL / 44',
    'XXXL / 46',
    '4XL / 48',
    '5XL / 50',
    '24',
    '6XL / 52',
    '25',
    '7XL / 54',
    '26',
    '8XL / 56',
    '27',
    '9XL / 58',
    '28',
    '10XL / 60',
    '29',
    '30',
    '31',
    '32',
    '33'
  ];

  static const List<String> _menSizes = [
    'L',
    'L/XL',
    'XL',
    'XXL',
    '2XL',
    '3XL',
    '4XL',
    '5XL',
    '6XL',
    '7XL',
    '29',
    '30',
    '31',
    '32',
    '33',
    '34',
    '36',
    '38',
    '40',
    '42',
    '44',
    '46',
    '48',
    '50',
    '52',
    '54',
    '56',
    '58',
    'XXXL',
    '8XL',
    'XS',
    'S',
    'S/M',
    'M'
  ];

  late final List<String> _sizes;
  late List<String> _selectedSizes;
  late List<String> _selectedFabricTypes;

  @override
  void initState() {
    super.initState();
    // pick which size‐list to show based on widget.category:
    _sizes = widget.category == 'Men' ? _menSizes : _womenSizes;

    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedSizes =
          List<String>.from(widget.initialAttributes!['pantSizes'] ?? []);

      // Load fabric types with backward compatibility
      if (widget.initialAttributes!['pantFabricTypes'] != null) {
        // New format: array
        _selectedFabricTypes =
            List<String>.from(widget.initialAttributes!['pantFabricTypes']);
      } else if (widget.initialAttributes!['pantFabricType'] != null) {
        // Legacy format: single string - convert to array
        final legacyType = widget.initialAttributes!['pantFabricType'] as String;
        _selectedFabricTypes = [legacyType];
      } else {
        _selectedFabricTypes = <String>[];
      }
    } else {
      _selectedSizes = <String>[];
      _selectedFabricTypes = <String>[];
    }
  }

  void _handleFabricTypeToggle(String fabricType) {
    setState(() {
      if (_selectedFabricTypes.contains(fabricType)) {
        // Already selected - remove it
        _selectedFabricTypes.remove(fabricType);
      } else if (_selectedFabricTypes.length < _maxFabricTypes) {
        // Not selected and under limit - add it
        _selectedFabricTypes.add(fabricType);
      }
      // If at limit and trying to add, do nothing
    });
  }

  void _savePantDetails() {
    final l10n = AppLocalizations.of(context);

    if (_selectedFabricTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectAtLeastOneFabricType),
        ),
      );
      return;
    }

    if (_selectedSizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectAllClothingDetails),
        ),
      );
      return;
    }

    // Return the pant details as dynamic attributes
    final result = <String, dynamic>{
      'pantSizes': _selectedSizes.toList(),
      'pantFabricTypes': _selectedFabricTypes.toList(),
    };

    // Include any existing attributes that were passed in
    if (widget.initialAttributes != null) {
      widget.initialAttributes!.forEach((key, value) {
        // Skip keys we're setting, and remove legacy pantFabricType
        if (!result.containsKey(key) && key != 'pantFabricType') {
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
    final isAtFabricLimit = _selectedFabricTypes.length >= _maxFabricTypes;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          l10n.clothingDetails,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Container(
        color: isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fabric Type Section
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Text(
                            l10n.fabricType,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${_selectedFabricTypes.length}/$_maxFabricTypes)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Fabric limit warning
                    if (isAtFabricLimit)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.orange[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.maxFabricTypesSelected,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 8),

                    // Fabric Type Grid
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            AllInOneCategoryData.kClothingTypes.map((type) {
                          final selected = _selectedFabricTypes.contains(type);
                          final disabled = !selected && isAtFabricLimit;

                          return GestureDetector(
                            onTap:
                                disabled ? null : () => _handleFabricTypeToggle(type),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.1)
                                    : disabled
                                        ? (isDark
                                            ? const Color(0xFF21202A)
                                                .withOpacity(0.5)
                                            : Colors.grey[200])
                                        : (isDark
                                            ? const Color(0xFF21202A)
                                            : Colors.white),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (selected) ...[
                                    Icon(
                                      Icons.check,
                                      size: 16,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    AllInOneCategoryData.localizeClothingType(
                                        type, l10n),
                                    style: TextStyle(
                                      color: disabled
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(0.4)
                                          : selected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Size Section Header
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        l10n.selectAvailableSizes,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Grid of sizes
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.5,
                        ),
                        itemCount: _sizes.length,
                        itemBuilder: (ctx, i) {
                          final size = _sizes[i];
                          final selected = _selectedSizes.contains(size);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _selectedSizes.remove(size);
                              } else {
                                _selectedSizes.add(size);
                              }
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.1)
                                    : (isDark
                                        ? const Color(0xFF21202A)
                                        : Colors.white),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  size,
                                  style: TextStyle(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savePantDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A86B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(l10n.save, style: const TextStyle(fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}