import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import 'dart:io';

class ListColorOptionScreen extends StatefulWidget {
  final Map<String, XFile?>? initialSelectedColors;
  final Map<String, Map<String, dynamic>>? initialColorData;
  final Map<String, List<String>>? existingColorImageUrls;

  const ListColorOptionScreen({
    Key? key,
    this.initialSelectedColors,
    this.initialColorData,
    this.existingColorImageUrls,
  }) : super(key: key);

  @override
  _ListColorOptionScreenState createState() => _ListColorOptionScreenState();
}

class _ListColorOptionScreenState extends State<ListColorOptionScreen> {
  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blue', 'color': Colors.blue},
    {'name': 'Orange', 'color': Colors.orange},
    {'name': 'Yellow', 'color': Colors.yellow},
    {'name': 'Black', 'color': Colors.black},
    {'name': 'Brown', 'color': Colors.brown},
    {'name': 'Dark Blue', 'color': const Color(0xFF00008B)},
    {'name': 'Gray', 'color': Colors.grey},
    {'name': 'Pink', 'color': Colors.pink},
    {'name': 'Red', 'color': Colors.red},
    {'name': 'White', 'color': Colors.white},
    {'name': 'Green', 'color': Colors.green},
    {'name': 'Purple', 'color': Colors.purple},
    {'name': 'Teal', 'color': Colors.teal},
    {'name': 'Lime', 'color': Colors.lime},
    {'name': 'Cyan', 'color': Colors.cyan},
    {'name': 'Magenta', 'color': const Color(0xFFFF00FF)},
    {'name': 'Indigo', 'color': Colors.indigo},
    {'name': 'Amber', 'color': Colors.amber},
    {'name': 'Deep Orange', 'color': Colors.deepOrange},
    {'name': 'Light Blue', 'color': Colors.lightBlue},
    {'name': 'Deep Purple', 'color': Colors.deepPurple},
    {'name': 'Light Green', 'color': Colors.lightGreen},
    {'name': 'Dark Gray', 'color': const Color(0xFF444444)},
    {'name': 'Beige', 'color': const Color(0xFFF5F5DC)},
    {'name': 'Turquoise', 'color': const Color(0xFF40E0D0)},
    {'name': 'Violet', 'color': const Color(0xFFEE82EE)},
    {'name': 'Olive', 'color': const Color(0xFF808000)},
    {'name': 'Maroon', 'color': const Color(0xFF800000)},
    {'name': 'Navy', 'color': const Color(0xFF000080)},
    {'name': 'Silver', 'color': const Color(0xFFC0C0C0)},
  ];

   ImageProvider _getImageProvider(dynamic image) {
    if (image is XFile) {
      // New image picked from gallery
      return FileImage(File(image.path));
    } else if (image is String) {
      // Existing image URL from Firestore
      return NetworkImage(image);
    } else {
      // Fallback (should never happen, but safe)
      throw Exception('Unsupported image type: ${image.runtimeType}');
    }
  }

  Map<String, Map<String, dynamic>> _selectedColors = {};
  bool? _wantsColorOptions;

  String getLocalizedColorName(String colorName, AppLocalizations l10n) {
    switch (colorName) {
      case 'Blue':
        return l10n.colorBlue;
      case 'Orange':
        return l10n.colorOrange;
      case 'Yellow':
        return l10n.colorYellow;
      case 'Black':
        return l10n.colorBlack;
      case 'Brown':
        return l10n.colorBrown;
      case 'Dark Blue':
        return l10n.colorDarkBlue;
      case 'Gray':
        return l10n.colorGray;
      case 'Pink':
        return l10n.colorPink;
      case 'Red':
        return l10n.colorRed;
      case 'White':
        return l10n.colorWhite;
      case 'Green':
        return l10n.colorGreen;
      case 'Purple':
        return l10n.colorPurple;
      case 'Teal':
        return l10n.colorTeal;
      case 'Lime':
        return l10n.colorLime;
      case 'Cyan':
        return l10n.colorCyan;
      case 'Magenta':
        return l10n.colorMagenta;
      case 'Indigo':
        return l10n.colorIndigo;
      case 'Amber':
        return l10n.colorAmber;
      case 'Deep Orange':
        return l10n.colorDeepOrange;
      case 'Light Blue':
        return l10n.colorLightBlue;
      case 'Deep Purple':
        return l10n.colorDeepPurple;
      case 'Light Green':
        return l10n.colorLightGreen;
      case 'Dark Gray':
        return l10n.colorDarkGray;
      case 'Beige':
        return l10n.colorBeige;
      case 'Turquoise':
        return l10n.colorTurquoise;
      case 'Violet':
        return l10n.colorViolet;
      case 'Olive':
        return l10n.colorOlive;
      case 'Maroon':
        return l10n.colorMaroon;
      case 'Navy':
        return l10n.colorNavy;
      case 'Silver':
        return l10n.colorSilver;
      default:
        return colorName;
    }
  }

  @override
    void initState() {
    super.initState();

    // Check if we have full color data (with quantities) or just images
    if (widget.initialColorData != null) {
      _wantsColorOptions = true;
      _selectedColors = Map<String, Map<String, dynamic>>.from(widget.initialColorData!);
      
      // ✅ ADD: Load existing image URLs if no XFile is present
      if (widget.existingColorImageUrls != null) {
        widget.existingColorImageUrls!.forEach((color, urls) {
          if (_selectedColors.containsKey(color) && 
              _selectedColors[color]!['image'] == null &&
              urls.isNotEmpty) {
            _selectedColors[color]!['image'] = urls[0]; // Use first URL as String
          }
        });
      }
    } else if (widget.initialSelectedColors != null) {
      // Legacy support: just images without quantities
      _wantsColorOptions = null;
      for (var entry in widget.initialSelectedColors!.entries) {
        _selectedColors[entry.key] = {
          'image': entry.value,
          'quantity': null,
        };
      }
    } else {
      _wantsColorOptions = null;
    }
  }

 void _handleContinue(AppLocalizations l10n) {
  print('🎨 _handleContinue called');
  print('🎨 _selectedColors: $_selectedColors');
  
  if (_selectedColors.isEmpty) {
    print('🎨 No colors selected - returning empty map');
    context.pop({}); // ✅ Return empty map to clear colors
    return;
  }
    for (var entry in _selectedColors.entries) {
      final image = entry.value['image'];
      final quantity = entry.value['quantity'] as int?;
      if (image == null || quantity == null || quantity <= 0) {
        showCupertinoDialog(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            content: Text(
              l10n.colorOptionWarning,
              style: const TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  l10n.okay,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }
    }
    final result = _selectedColors.map<String, Map<String, dynamic>>(
      (key, value) => MapEntry(key, {
        'image': value['image'],
        'quantity': value['quantity'],
      }),
    );
    context.pop(result);
  }

  Future<void> _pickImageForColor(String colorName) async {
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.gallery);
    if (pickedImage != null) {
      setState(() {
        _selectedColors[colorName]!['image'] = pickedImage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          actions: [
            if (_wantsColorOptions == true)
              TextButton(
                onPressed: () => _handleContinue(l10n),
                child: Text(
                  l10n.continueText,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.grey[100],
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.moreColorOptions,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color.fromARGB(
                              255, 45, 43, 60) // dark‐mode row background
                          : Colors.white,
                      child: RadioListTile<bool>(
                        title: Text(l10n.yes),
                        value: true,
                        groupValue: _wantsColorOptions,
                        onChanged: (value) => setState(() {
                          _wantsColorOptions = true;
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: const Color(0xFF00A86B),
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[300]),
                   Container(
  width: double.infinity,
  color: Theme.of(context).brightness == Brightness.dark
      ? const Color.fromARGB(255, 45, 43, 60)
      : Colors.white,
  child: RadioListTile<bool>(
    title: Text(l10n.no),
    value: false,
    groupValue: _wantsColorOptions,
    onChanged: (value) {
      print('🎨 User clicked NO - returning empty map');
      context.pop({}); // ✅ Return empty map to clear colors
    },
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: const Color(0xFF00A86B),
  ),
),
                    if (_wantsColorOptions == true) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.selectColors,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Use more columns and less spacing on tablets
                          final isTablet = constraints.maxWidth >= 600;
                          final crossAxisCount = isTablet ? 7 : 5;
                          final mainAxisSpacing = isTablet ? 6.0 : 10.0;
                          final crossAxisSpacing = isTablet ? 8.0 : 10.0;

                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: crossAxisSpacing,
                              mainAxisSpacing: mainAxisSpacing,
                              childAspectRatio: 0.7,
                            ),
                            itemCount: _availableColors.length,
                            itemBuilder: (context, index) {
                          final colorData = _availableColors[index];
                          final colorName = colorData['name'] as String;
                          final colorValue = colorData['color'] as Color;
                          final isSelected =
                              _selectedColors.containsKey(colorName);
                          final localizedName =
                              getLocalizedColorName(colorName, l10n);

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                FocusScope.of(context).unfocus();
                                if (isSelected) {
                                  _selectedColors.remove(colorName);
                                } else {
                                  _selectedColors[colorName] = {
                                    'image': null,
                                    'quantity': null,
                                  };
                                }
                              });
                            },
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colorValue,
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  localizedName,
                                  style: const TextStyle(fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            );
                          },
                        );
                        },
                      ),
                      if (_selectedColors.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? const Color.fromARGB(
                                    255, 45, 43, 60) // dark‐mode row background
                                : Colors.white,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16.0,
                                  left: 16.0,
                                  right: 16.0,
                                ),
                                child: Text(
                                  l10n.pleaseAddImageForColor,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ..._selectedColors.keys.map((colorName) {
                                final data = _selectedColors[colorName]!;
                                final image = data['image'];
                                final quantity = data['quantity'];
                                final localizedName =
                                    getLocalizedColorName(colorName, l10n);
                                const double pickerSize = 80.0;
                                const Color borderColor = Colors.grey;
                                const Color cameraIconColor = Color(0xFFFFA726);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _availableColors.firstWhere(
                                              (c) =>
                                                  c['name'] ==
                                                  colorName)['color'] as Color,
                                          border: Border.all(
                                            color: Colors.grey.shade400,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              localizedName,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(height: 4),
                                            TextFormField(
                                              initialValue: quantity != null && quantity > 0
                                                  ? quantity.toString()
                                                  : null,
                                              decoration: InputDecoration(
                                                hintText: l10n.quantity,
                                                hintStyle: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 14,
                                                ),
                                                border:
                                                    const UnderlineInputBorder(),
                                                helperText: (quantity == null ||
                                                        quantity == 0)
                                                    ? l10n.required
                                                    : null,
                                                helperStyle: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedColors[colorName]![
                                                          'quantity'] =
                                                      int.tryParse(value) ?? 0;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                        GestureDetector(
  onTap: () {
    FocusScope.of(context).unfocus();
    _pickImageForColor(colorName);
  },
  child: Container(
    width: pickerSize,
    height: pickerSize,
    decoration: BoxDecoration(
      border: Border.all(color: borderColor, width: 1.5),
      borderRadius: BorderRadius.circular(6),
      image: image != null
          ? DecorationImage(
              image: _getImageProvider(image), // ✅ Use helper method
              fit: BoxFit.cover,
            )
          : null,
    ),
    child: image == null
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt,
                size: 32,
                color: cameraIconColor,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.addImage,
                style: const TextStyle(
                  fontSize: 12,
                  color: cameraIconColor,
                ),
              ),
            ],
          )
        : null,
  ),
),

                                    ],
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}
