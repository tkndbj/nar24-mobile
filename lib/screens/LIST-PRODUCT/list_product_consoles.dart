// File: list_product_consoles.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductConsolesScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductConsolesScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductConsolesScreenState createState() =>
      _ListProductConsolesScreenState();
}

class _ListProductConsolesScreenState extends State<ListProductConsolesScreen> {
  // Console brands
  static const List<String> _consoleBrands = [
    'PlayStation',
    'Xbox',
    'Nintendo',
    'PC',
    'Mobile',
    'Retro',
  ];

  // Console variants for each brand
  static const Map<String, List<String>> _consoleVariants = {
    'PlayStation': [
      'PS5',
      'PS5_Digital',
      'PS5_Slim',
      'PS5_Pro',
      'PS4',
      'PS4_Slim',
      'PS4_Pro',
      'PS3',
      'PS2',
      'PS1',
      'PSP',
      'PS_Vita',
    ],
    'Xbox': [
      'Xbox_Series_X',
      'Xbox_Series_S',
      'Xbox_One_X',
      'Xbox_One_S',
      'Xbox_One',
      'Xbox_360',
      'Xbox_Original',
    ],
    'Nintendo': [
      'Switch_OLED',
      'Switch_Standard',
      'Switch_Lite',
      'Wii_U',
      'Wii',
      'GameCube',
      'N64',
      'SNES',
      'NES',
      '3DS_XL',
      '3DS',
      '2DS',
      'DS_Lite',
      'DS',
      'Game_Boy_Advance',
      'Game_Boy_Color',
      'Game_Boy',
    ],
    'PC': [
      'Steam_Deck',
      'Gaming_PC',
      'Gaming_Laptop',
      'Mini_PC',
    ],
    'Mobile': [
      'iOS',
      'Android',
      'Steam_Deck',
    ],
    'Retro': [
      'Atari_2600',
      'Sega_Genesis',
      'Sega_Dreamcast',
      'Neo_Geo',
      'Arcade_Cabinet',
    ],
  };

  String? _selectedBrand;
  String? _selectedVariant;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedBrand =
          widget.initialAttributes!['productType'] as String? ??
          widget.initialAttributes!['consoleBrand'] as String?;
      _selectedVariant = widget.initialAttributes!['consoleVariant'] as String?;
    }
  }

  String _localizedBrand(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'PlayStation':
        return l10n.consoleBrandPlayStation;
      case 'Xbox':
        return l10n.consoleBrandXbox;
      case 'Nintendo':
        return l10n.consoleBrandNintendo;
      case 'PC':
        return l10n.consoleBrandPC;      
      case 'Retro':
        return l10n.consoleBrandRetro;
      default:
        return raw;
    }
  }

  String _localizedVariant(String raw, AppLocalizations l10n) {
    switch (raw) {
      // PlayStation variants
      case 'PS5':
        return l10n.consoleVariantPS5;
      case 'PS5_Digital':
        return l10n.consoleVariantPS5Digital;
      case 'PS5_Slim':
        return l10n.consoleVariantPS5Slim;
      case 'PS5_Pro':
        return l10n.consoleVariantPS5Pro;
      case 'PS4':
        return l10n.consoleVariantPS4;
      case 'PS4_Slim':
        return l10n.consoleVariantPS4Slim;
      case 'PS4_Pro':
        return l10n.consoleVariantPS4Pro;
      case 'PS3':
        return l10n.consoleVariantPS3;
      case 'PS2':
        return l10n.consoleVariantPS2;
      case 'PS1':
        return l10n.consoleVariantPS1;
      case 'PSP':
        return l10n.consoleVariantPSP;
      case 'PS_Vita':
        return l10n.consoleVariantPSVita;
      
      // Xbox variants
      case 'Xbox_Series_X':
        return l10n.consoleVariantXboxSeriesX;
      case 'Xbox_Series_S':
        return l10n.consoleVariantXboxSeriesS;
      case 'Xbox_One_X':
        return l10n.consoleVariantXboxOneX;
      case 'Xbox_One_S':
        return l10n.consoleVariantXboxOneS;
      case 'Xbox_One':
        return l10n.consoleVariantXboxOne;
      case 'Xbox_360':
        return l10n.consoleVariantXbox360;
      case 'Xbox_Original':
        return l10n.consoleVariantXboxOriginal;
      
      // Nintendo variants
      case 'Switch_OLED':
        return l10n.consoleVariantSwitchOLED;
      case 'Switch_Standard':
        return l10n.consoleVariantSwitchStandard;
      case 'Switch_Lite':
        return l10n.consoleVariantSwitchLite;
      case 'Wii_U':
        return l10n.consoleVariantWiiU;
      case 'Wii':
        return l10n.consoleVariantWii;
      case 'GameCube':
        return l10n.consoleVariantGameCube;
      case 'N64':
        return l10n.consoleVariantN64;
      case 'SNES':
        return l10n.consoleVariantSNES;
      case 'NES':
        return l10n.consoleVariantNES;
      case '3DS_XL':
        return l10n.consoleVariant3DSXL;
      case '3DS':
        return l10n.consoleVariant3DS;
      case '2DS':
        return l10n.consoleVariant2DS;
      case 'DS_Lite':
        return l10n.consoleVariantDSLite;
      case 'DS':
        return l10n.consoleVariantDS;
      case 'Game_Boy_Advance':
        return l10n.consoleVariantGameBoyAdvance;
      case 'Game_Boy_Color':
        return l10n.consoleVariantGameBoyColor;
      case 'Game_Boy':
        return l10n.consoleVariantGameBoy;
      
      // PC variants
      case 'Steam_Deck':
        return l10n.consoleVariantSteamDeck;
      case 'Gaming_PC':
        return l10n.consoleVariantGamingPC;
      case 'Gaming_Laptop':
        return l10n.consoleVariantGamingLaptop;
      case 'Mini_PC':
        return l10n.consoleVariantMiniPC;
      
    
      
      // Retro variants
      case 'Atari_2600':
        return l10n.consoleVariantAtari2600;
      case 'Sega_Genesis':
        return l10n.consoleVariantSegaGenesis;
      case 'Sega_Dreamcast':
        return l10n.consoleVariantSegaDreamcast;
      case 'Neo_Geo':
        return l10n.consoleVariantNeoGeo;
      case 'Arcade_Cabinet':
        return l10n.consoleVariantArcadeCabinet;
      
      default:
        return raw;
    }
  }

  void _saveConsoleSelection() {
    if (_selectedBrand == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseSelectConsoleBrand),
        ),
      );
      return;
    }

    if (_selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseSelectConsoleVariant),
        ),
      );
      return;
    }

    // Return the console selection as unified productType + variant
    final result = <String, dynamic>{
      'productType': _selectedBrand,
      'consoleVariant': _selectedVariant,
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
          l10n.selectConsole,
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
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Console Brand Section
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.selectConsoleBrand,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ..._consoleBrands.map((brand) {
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: isDark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: RadioListTile<String>(
                                title: Text(
                                  _localizedBrand(brand, l10n),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                value: brand,
                                groupValue: _selectedBrand,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBrand = value;
                                    _selectedVariant = null; // Reset variant when brand changes
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

                      // Console Variant Section (only show if brand is selected)
                      if (_selectedBrand != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            l10n.selectConsoleVariant,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...(_consoleVariants[_selectedBrand] ?? []).map((variant) {
                          return Column(
                            children: [
                              Container(
                                width: double.infinity,
                                color: isDark
                                    ? const Color.fromARGB(255, 45, 43, 60)
                                    : Colors.white,
                                child: RadioListTile<String>(
                                  title: Text(
                                    _localizedVariant(variant, l10n),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  value: variant,
                                  groupValue: _selectedVariant,
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedVariant = value;
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
                      ],
                      
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
                    onPressed: _saveConsoleSelection,
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