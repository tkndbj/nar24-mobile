import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductGenderScreen extends StatefulWidget {
  final String? category;
  final String? subcategory;
  final String? subsubcategory;
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductGenderScreen({
    Key? key,
    this.category,
    this.subcategory,
    this.subsubcategory,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductGenderScreenState createState() =>
      _ListProductGenderScreenState();
}

class _ListProductGenderScreenState extends State<ListProductGenderScreen> {
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedGender = widget.initialAttributes!['gender'] as String?;
    }
  }

  void _saveGender() {
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).pleaseSelectAllClothingDetails)),
      );
      return;
    }

    // Return the gender as dynamic attributes
    final result = <String, dynamic>{
      'gender': _selectedGender,
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.gender,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Container(
        color: isDarkMode ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.gender,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                width: double.infinity,
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                child: RadioListTile<String>(
                  title: Text(l10n.clothingGenderWomen),
                  value: 'Women',
                  groupValue: _selectedGender,
                  onChanged: (String? value) {
                    setState(() {
                      _selectedGender = value;
                    });
                  },
                  activeColor: const Color(0xFF00A86B),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey[300],
              ),
              Container(
                width: double.infinity,
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                child: RadioListTile<String>(
                  title: Text(l10n.clothingGenderMen),
                  value: 'Men',
                  groupValue: _selectedGender,
                  onChanged: (String? value) {
                    setState(() {
                      _selectedGender = value;
                    });
                  },
                  activeColor: const Color(0xFF00A86B),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey[300],
              ),
              Container(
                width: double.infinity,
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                child: RadioListTile<String>(
                  title: Text(l10n.clothingGenderUnisex),
                  value: 'Unisex',
                  groupValue: _selectedGender,
                  onChanged: (String? value) {
                    setState(() {
                      _selectedGender = value;
                    });
                  },
                  activeColor: const Color(0xFF00A86B),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveGender,
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
