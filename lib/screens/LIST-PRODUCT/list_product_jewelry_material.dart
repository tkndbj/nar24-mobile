// File: list_product_jewelry_material.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductJewelryMaterialScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductJewelryMaterialScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductJewelryMaterialScreenState createState() =>
      _ListProductJewelryMaterialScreenState();
}

class _ListProductJewelryMaterialScreenState
    extends State<ListProductJewelryMaterialScreen> {
  static const List<String> _materialKeys = [
    'Iron',
    'Steel',
    'Gold',
    'Silver',
    'Diamond',
    'Copper',
  ];
  List<String> _selectedMaterials = [];

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedMaterials = List<String>.from(
          widget.initialAttributes!['jewelryMaterials'] ?? []);
    }
  }

  String _localizedMaterial(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'Iron':
        return l10n.jewelryMaterialIron;
      case 'Steel':
        return l10n.jewelryMaterialSteel;
      case 'Gold':
        return l10n.jewelryMaterialGold;
      case 'Silver':
        return l10n.jewelryMaterialSilver;
      case 'Diamond':
        return l10n.jewelryMaterialDiamond;
      case 'Copper':
        return l10n.jewelryMaterialCopper;
      default:
        return raw;
    }
  }

  void _saveJewelryMaterials() {
    if (_selectedMaterials.isEmpty) {
      // Allow saving with no materials if needed, or show validation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).pleaseSelectAllClothingDetails),
        ),
      );
      return;
    }

    // Return the jewelry materials as dynamic attributes
    final result = <String, dynamic>{
      'jewelryMaterials': _selectedMaterials,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectJewelryMaterial,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          color: isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
          child: Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: _materialKeys.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                  ),
                  itemBuilder: (context, index) {
                    final raw = _materialKeys[index];
                    final isChecked = _selectedMaterials.contains(raw);
                    return CheckboxListTile(
                      title: Text(_localizedMaterial(raw, l10n)),
                      value: isChecked,
                      onChanged: (_) {
                        setState(() {
                          if (isChecked) {
                            _selectedMaterials.remove(raw);
                          } else {
                            _selectedMaterials.add(raw);
                          }
                        });
                      },
                      activeColor: const Color(0xFF00A86B),
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveJewelryMaterials,
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
