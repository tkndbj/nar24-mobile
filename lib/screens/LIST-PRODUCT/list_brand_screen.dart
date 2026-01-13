import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../constants/brands.dart'; // Import the single global brands file

class ListBrandScreen extends StatefulWidget {
  final String category;
  final String? subcategory;
  final String? subsubcategory;
  final String? initialBrand;
  // Remove all the hard-coded initial fields - they should come from dynamic attributes
  final Map<String, dynamic>? initialAttributes;

  const ListBrandScreen({
    Key? key,
    required this.category,
    this.subcategory,
    this.subsubcategory,
    this.initialBrand,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListBrandScreenState createState() => _ListBrandScreenState();
}

class _ListBrandScreenState extends State<ListBrandScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _brands = [];  
  String? _selectedBrand;

  @override
  void initState() {
    super.initState();
    _loadBrands();
    
    _selectedBrand = widget.initialBrand;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadBrands() {
    // Use the single global brands list for all categories
    // This provides access to all 3000+ brands regardless of category
    _brands = globalBrands;
    
  }
  

  void _selectBrand(String brand) {
    setState(() {
      _selectedBrand = brand;
    });

    // Simply return the selected brand and let the dynamic flow system handle the next step
    final result = <String, dynamic>{
      'brand': brand,
    };

    // Include any existing attributes that were passed in
    if (widget.initialAttributes != null) {
      result.addAll(widget.initialAttributes!);
    }

    context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectBrand,
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
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color.fromARGB(255, 41, 38, 59)
                    : Colors.grey[100],
                hintText: l10n.searchBrand,
                hintStyle: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: const Color(0xFF00A86B),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(color: Colors.grey[100]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(color: Colors.grey[100]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide(color: Colors.grey[100]!),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
              ),
            ),
          ),
          
          
          Expanded(
            child: ListView.builder(              
              itemBuilder: (context, index) {
                final brand = _brands[index];
                final isSelected = _selectedBrand == brand;

                return ListTile(
                  title: Text(
                    brand,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      if (value == true) {
                        _selectBrand(brand);
                      }
                    },
                    activeColor: const Color(0xFF00A86B),
                  ),
                  onTap: () {
                    _selectBrand(brand);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
