// File: list_product_white_goods.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductWhiteGoodsScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductWhiteGoodsScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductWhiteGoodsScreenState createState() =>
      _ListProductWhiteGoodsScreenState();
}

class _ListProductWhiteGoodsScreenState
    extends State<ListProductWhiteGoodsScreen> {
  // white goods appliance keys
  static const List<String> _whiteGoodsKeys = [
    'Refrigerator',
    'WashingMachine',
    'Dishwasher',
    'Dryer',
    'Freezer',
  ];
  String? _selectedWhiteGood;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedWhiteGood = widget.initialAttributes!['whiteGood'] as String?;
    }
  }

  String _localizedWhiteGood(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'Refrigerator':
        return l10n.whiteGoodRefrigerator;
      case 'WashingMachine':
        return l10n.whiteGoodWashingMachine;
      case 'Dishwasher':
        return l10n.whiteGoodDishwasher;
      case 'Dryer':
        return l10n.whiteGoodDryer;
      case 'Freezer':
        return l10n.whiteGoodFreezer;
      default:
        return raw;
    }
  }

  void _saveWhiteGood() {
    if (_selectedWhiteGood == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).pleaseSelectWhiteGood),
        ),
      );
      return;
    }

    // Return the white good as dynamic attributes
    final result = <String, dynamic>{
      'whiteGood': _selectedWhiteGood,
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
          l10n.selectWhiteGood,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          color: isDark 
              ? const Color.fromARGB(255, 33, 31, 49)
              : const Color(0xFFF5F5F5),
          child: Column(
            children: [
              // Scrollable list of white goods
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.selectWhiteGoodType,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ..._whiteGoodsKeys.map((whiteGood) {
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: isDark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: RadioListTile<String>(
                                title: Text(
                                  _localizedWhiteGood(whiteGood, l10n),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                value: whiteGood,
                                groupValue: _selectedWhiteGood,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedWhiteGood = value;
                                  });
                                },
                                activeColor: const Color(0xFF00A86B),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark 
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

              // Pinned Save button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveWhiteGood,
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