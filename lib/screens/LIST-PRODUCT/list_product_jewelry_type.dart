// File: list_product_jewelry_type.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductJewelryTypeScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductJewelryTypeScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductJewelryTypeScreenState createState() =>
      _ListProductJewelryTypeScreenState();
}

class _ListProductJewelryTypeScreenState
    extends State<ListProductJewelryTypeScreen> {
  // raw type keys
  static const List<String> _typeKeys = [
    'Necklace',
    'Earring',
    'Piercing',
    'Ring',
    'Bracelet',
    'Anklet',
    'NoseRing',
    'Set',
  ];
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedType = widget.initialAttributes!['jewelryType'] as String?;
    }
  }

  String _localizedType(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'Necklace':
        return l10n.jewelryTypeNecklace;
      case 'Earring':
        return l10n.jewelryTypeEarring;
      case 'Piercing':
        return l10n.jewelryTypePiercing;
      case 'Ring':
        return l10n.jewelryTypeRing;
      case 'Bracelet':
        return l10n.jewelryTypeBracelet;
      case 'Anklet':
        return l10n.jewelryTypeAnklet;
      case 'NoseRing':
        return l10n.jewelryTypeNoseRing;
      case 'Set':
        return l10n.jewelryTypeSet;
      default:
        return raw;
    }
  }

  void _saveJewelryType() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).pleaseSelectAllClothingDetails),
        ),
      );
      return;
    }

    // Return the jewelry type as dynamic attributes
    final result = <String, dynamic>{
      'jewelryType': _selectedType,
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
          l10n.selectJewelryType,
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
                  itemCount: _typeKeys.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                  ),
                  itemBuilder: (context, index) {
                    final raw = _typeKeys[index];
                    return RadioListTile<String>(
                      title: Text(_localizedType(raw, l10n)),
                      value: raw,
                      groupValue: _selectedType,
                      onChanged: (val) => setState(() => _selectedType = val),
                      activeColor: const Color(0xFF00A86B),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveJewelryType,
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
