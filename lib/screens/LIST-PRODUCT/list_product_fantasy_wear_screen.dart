import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/all_in_one_category_data.dart';
import 'package:go_router/go_router.dart';

class ListProductFantasyWearScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductFantasyWearScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductFantasyWearScreenState createState() =>
      _ListProductFantasyWearScreenState();
}

class _ListProductFantasyWearScreenState
    extends State<ListProductFantasyWearScreen> {
  String? _selectedType;

  // Raw fantasy wear type keys
  final List<String> _fantasyWearTypes = [
    'Lingerie',
    'Babydoll',
    'Chemise',
    'Teddy',
    'Bodysuit',
    'Corset',
    'Bustier',
    'Garter',
    'Robe',
    'Kimono',
    'Costume',
    'RolePlay',
    'Sleepwear',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedType =
          widget.initialAttributes!['productType'] as String? ??
          widget.initialAttributes!['fantasyWearType'] as String?;
    }
  }

  void _saveFantasyWear() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).pleaseSelectFantasyWearType),
        ),
      );
      return;
    }

    // Return the fantasy wear type as unified productType
    final result = <String, dynamic>{
      'productType': _selectedType,
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

  String _localizeFantasyWearType(String type) {
    return AllInOneCategoryData.localizeFantasyWearType(
        type, AppLocalizations.of(context));
  }

  String _getFantasyWearIcon(String type) {
    const iconMap = {
      'Lingerie': '👙',
      'Babydoll': '💃',
      'Chemise': '👗',
      'Teddy': '🧸',
      'Bodysuit': '🩱',
      'Corset': '🎀',
      'Bustier': '💎',
      'Garter': '🎗️',
      'Robe': '🥻',
      'Kimono': '👘',
      'Costume': '🎭',
      'RolePlay': '🎪',
      'Sleepwear': '🌙',
      'Other': '✨',
    };
    return iconMap[type] ?? '💫';
  }

  Color _getPrimaryColor(String type) {
    const colorMap = {
      'Lingerie': Color(0xFFEC4899), // pink
      'Babydoll': Color(0xFF9333EA), // purple
      'Chemise': Color(0xFFF43F5E), // rose
      'Teddy': Color(0xFFD946EF), // fuchsia
      'Bodysuit': Color(0xFF8B5CF6), // violet
      'Corset': Color(0xFFEF4444), // red
      'Bustier': Color(0xFFEC4899), // pink
      'Garter': Color(0xFFF43F5E), // rose
      'Robe': Color(0xFF9333EA), // purple
      'Kimono': Color(0xFF6366F1), // indigo
      'Costume': Color(0xFFD946EF), // fuchsia
      'RolePlay': Color(0xFF9333EA), // purple
      'Sleepwear': Color(0xFF3B82F6), // blue
      'Other': Color(0xFF8B5CF6), // violet
    };
    return colorMap[type] ?? const Color(0xFF9333EA);
  }

  Color _getSecondaryColor(String type) {
    const colorMap = {
      'Lingerie': Color(0xFFF43F5E), // rose
      'Babydoll': Color(0xFFEC4899), // pink
      'Chemise': Color(0xFFEC4899), // pink
      'Teddy': Color(0xFF9333EA), // purple
      'Bodysuit': Color(0xFF9333EA), // purple
      'Corset': Color(0xFFF43F5E), // rose
      'Bustier': Color(0xFFD946EF), // fuchsia
      'Garter': Color(0xFFEF4444), // red
      'Robe': Color(0xFF8B5CF6), // violet
      'Kimono': Color(0xFF9333EA), // purple
      'Costume': Color(0xFFEC4899), // pink
      'RolePlay': Color(0xFFD946EF), // fuchsia
      'Sleepwear': Color(0xFF6366F1), // indigo
      'Other': Color(0xFF9333EA), // purple
    };
    return colorMap[type] ?? const Color(0xFFEC4899);
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
          l10n.fantasyWearType,
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
          child: Column(
            children: [
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header section
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // Icon header
                            Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFEC4899),
                                      Color(0xFF9333EA)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Title
                            Text(
                              l10n.selectFantasyWearType,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            // Description
                            Text(
                              l10n.fantasyWearDescription,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      // Fantasy wear types list
                      ..._fantasyWearTypes.map((type) {
                        final isSelected = _selectedType == type;
                        final primaryColor = _getPrimaryColor(type);
                        final secondaryColor = _getSecondaryColor(type);

                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: isDark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedType = type;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 12.0),
                                  child: Row(
                                    children: [
                                      // Icon badge
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: isSelected
                                              ? LinearGradient(
                                                  colors: [
                                                    primaryColor,
                                                    secondaryColor
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : null,
                                          color: isSelected
                                              ? null
                                              : (isDark
                                                  ? Colors.grey[800]
                                                  : Colors.grey[200]),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Center(
                                          child: Text(
                                            _getFantasyWearIcon(type),
                                            style:
                                                const TextStyle(fontSize: 24),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Type name
                                      Expanded(
                                        child: Text(
                                          _localizeFantasyWearType(type),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? primaryColor
                                                : (isDark
                                                    ? Colors.white
                                                    : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      // Radio indicator
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: isSelected
                                              ? LinearGradient(
                                                  colors: [
                                                    primaryColor,
                                                    secondaryColor
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : null,
                                          border: Border.all(
                                            color: isSelected
                                                ? primaryColor
                                                : (isDark
                                                    ? Colors.grey[600]!
                                                    : Colors.grey[400]!),
                                            width: 2,
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Center(
                                                child: Icon(
                                                  Icons.circle,
                                                  size: 10,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                            ),
                          ],
                        );
                      }).toList(),

                      const SizedBox(height: 16),

                      // Selection indicator
                      if (_selectedType != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getPrimaryColor(_selectedType!)
                                      .withOpacity(0.1),
                                  _getSecondaryColor(_selectedType!)
                                      .withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _getPrimaryColor(_selectedType!)
                                    .withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        _getPrimaryColor(_selectedType!),
                                        _getSecondaryColor(_selectedType!)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.selectedType,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              _getPrimaryColor(_selectedType!),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _localizeFantasyWearType(
                                            _selectedType!),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _getSecondaryColor(
                                              _selectedType!),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Pinned Save Button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveFantasyWear,
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
