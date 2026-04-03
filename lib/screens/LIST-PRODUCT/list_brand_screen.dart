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
  final TextEditingController _manualBrandController = TextEditingController();
  List<String> _brands = [];
  List<String> _filteredBrands = [];
  String? _selectedBrand;
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _loadBrands();
    _selectedBrand = widget.initialBrand;
    _searchController.addListener(_filterBrands);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualBrandController.dispose();
    super.dispose();
  }

  void _loadBrands() {
    _brands = globalBrands;
    _filteredBrands = _brands;
  }

  void _filterBrands() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredBrands = _brands;
      } else {
        _filteredBrands = _brands
            .where((b) => b.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  /// Sanitizes and title-cases a brand name.
  /// Strips unsafe chars, collapses whitespace, caps each word.
  String _sanitizeBrand(String raw) {
    // 1. Remove anything that isn't a letter, number, space, hyphen, ampersand, period, or apostrophe
    final cleaned = raw.replaceAll(RegExp(r"[^\p{L}\p{N}\s\-&.']", unicode: true), '');
    // 2. Collapse multiple spaces into one and trim
    final trimmed = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 3. Title case: capitalize first letter of each word, lowercase the rest
    return trimmed.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  void _selectBrand(String brand) {
    final sanitized = _sanitizeBrand(brand);
    if (sanitized.isEmpty) return;

    setState(() {
      _selectedBrand = sanitized;
    });

    final result = <String, dynamic>{
      'brand': sanitized,
    };

    if (widget.initialAttributes != null) {
      result.addAll(widget.initialAttributes!);
    }

    context.pop(result);
  }

  void _submitManualBrand() {
    final text = _manualBrandController.text;
    final sanitized = _sanitizeBrand(text);
    if (sanitized.isNotEmpty && sanitized.length <= 40) {
      _selectBrand(sanitized);
    }
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
          l10n.selectBrand,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Toggle: List vs Manual
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color.fromARGB(255, 41, 38, 59) : Colors.grey[100],
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showManualInput = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_showManualInput
                              ? const Color(0xFF00A86B)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: Text(
                          l10n.selectFromList,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: !_showManualInput
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showManualInput = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _showManualInput
                              ? const Color(0xFF00A86B)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: Text(
                          l10n.enterManually,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _showManualInput
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Manual input OR search + list
          if (_showManualInput)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _manualBrandController,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark
                          ? const Color.fromARGB(255, 41, 38, 59)
                          : Colors.grey[100],
                      hintText: l10n.brandNamePlaceholder,
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      counterText: '',
                      suffixText: '${_manualBrandController.text.length}/40',
                      suffixStyle: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
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
                        borderSide: const BorderSide(color: Color(0xFF00A86B)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14.0, horizontal: 20.0),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _manualBrandController.text.trim().isNotEmpty &&
                            _manualBrandController.text.trim().length <= 40
                        ? _submitManualBrand
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      disabledBackgroundColor: Colors.grey[300],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.confirmBrand,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark
                      ? const Color.fromARGB(255, 41, 38, 59)
                      : Colors.grey[100],
                  hintText: l10n.searchBrand,
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF00A86B)),
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

            // Brand list
            Expanded(
              child: _filteredBrands.isEmpty && _searchController.text.trim().isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text(l10n.noBrandsFound,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              )),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => setState(() => _showManualInput = true),
                            child: Text(l10n.enterManually,
                                style: const TextStyle(color: Color(0xFF00A86B))),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredBrands.length,
                      itemBuilder: (context, index) {
                        final brand = _filteredBrands[index];
                        final isSelected = _selectedBrand == brand;
                        return ListTile(
                          title: Text(brand,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface)),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _selectBrand(brand),
                            activeColor: const Color(0xFF00A86B),
                          ),
                          onTap: () => _selectBrand(brand),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
