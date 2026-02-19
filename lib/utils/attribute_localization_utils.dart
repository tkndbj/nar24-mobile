// File: lib/utils/attribute_localization_utils.dart

import '../generated/l10n/app_localizations.dart';
import '../constants/all_in_one_category_data.dart';

class AttributeLocalizationUtils {
  /// Formats all attributes with localized titles and values
  static String formatAttributesDisplay(
      Map<String, dynamic> attributes, AppLocalizations l10n) {
    if (attributes.isEmpty) return '';

    final List<String> displayParts = [];

    attributes.forEach((key, value) {
      if (value == null) return;

      String displayValue = getLocalizedAttributeValue(key, value, l10n);
      if (displayValue.isNotEmpty) {
        String title = getLocalizedAttributeTitle(key, l10n);
        displayParts.add('$title: $displayValue');
      }
    });

    return displayParts.join('\n');
  }

  /// Gets localized title for an attribute key
  static String getLocalizedAttributeTitle(
      String attributeKey, AppLocalizations l10n) {
    switch (attributeKey) {
      // Gender
      case 'gender':
        return l10n.gender;

      // Clothing attributes
      case 'clothingSizes':
        return l10n.clothingSize;
      case 'clothingFit':
        return l10n.clothingFit;
      case 'clothingType':
        return l10n.clothingType;
      case 'clothingTypes':
  return l10n.clothingType;
      case 'pantFabricTypes':
  return l10n.fabricType;

      // Footwear attributes
      case 'footwearSizes':
        return l10n.size;

      // Pant attributes
      case 'pantSizes':
        return l10n.size;

      // Jewelry attributes
      case 'jewelryType':
        return l10n.jewelryType;
      case 'jewelryMaterials':
        return l10n.jewelryMaterial;

      // Computer component attributes
      case 'computerComponent':
        return l10n.computerComponent;

      // Console attributes
      case 'consoleBrand':
        return l10n.consoleBrand;
      case 'consoleVariant':
        return l10n.consoleVariant;

      // Unified product type
      case 'productType':
        return l10n.productType;

      // Kitchen appliance attributes
      case 'kitchenAppliance':
        return l10n.kitchenAppliance;

      // White goods attributes
      case 'whiteGood':
        return l10n.whiteGood;

      // Fantasy wear attributes
      case 'fantasyWearType':
        return l10n.fantasyWearType;

      case 'selectedColor':
        return l10n.color ?? 'Color';

      case 'selectedSize':
        return l10n.size ?? 'Size';

      case 'selectedGender':
        return l10n.gender;

      case 'selectedClothingFit':
        return l10n.clothingFit;

      case 'selectedClothingType':
        return l10n.clothingType;

      case 'selectedFootwearSize':
        return l10n.selectSize;

      case 'selectedJewelryType':
        return l10n.jewelryType;

      case 'selectedJewelryMaterial':
        return l10n.jewelryMaterial;

      case 'selectedComputerComponent':
        return l10n.computerComponent;

      case 'selectedConsoleBrand':
        return l10n.consoleBrand;

      case 'selectedConsoleVariant':
        return l10n.consoleVariant;

      case 'selectedKitchenAppliance':
        return l10n.kitchenAppliance;

      default:
        // Convert camelCase to Title Case as fallback
        return attributeKey
            .replaceAllMapped(
              RegExp(r'([A-Z])'),
              (match) => ' ${match.group(1)}',
            )
            .trim()
            .split(' ')
            .map((word) => word.isNotEmpty
                ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
                : word)
            .join(' ');
    }
  }

  /// Gets localized value(s) for an attribute
  static String getLocalizedAttributeValue(
      String attributeKey, dynamic value, AppLocalizations l10n) {
    if (value is List) {
      final localizedItems = value
          .map((item) => getLocalizedSingleValue(attributeKey, item, l10n))
          .toList();
      return localizedItems.join(', ');
    } else {
      return getLocalizedSingleValue(attributeKey, value, l10n);
    }
  }

  /// Localizes a single value based on attribute type
  static String getLocalizedSingleValue(
      String attributeKey, dynamic value, AppLocalizations l10n) {
    final stringValue = value.toString();

    switch (attributeKey) {
      case 'gender':
        return localizeGender(stringValue, l10n);

      case 'clothingSizes':
        return localizeClothingSize(stringValue, l10n);

      case 'clothingFit':
        return localizeClothingFit(stringValue, l10n);

      case 'clothingType':
        return localizeClothingType(stringValue, l10n);
      case 'clothingTypes':
  return localizeClothingType(stringValue, l10n);

      case 'jewelryType':
        return localizeJewelryType(stringValue, l10n);

      case 'jewelryMaterials':
        return localizeJewelryMaterial(stringValue, l10n);
      case 'pantFabricTypes':
  return localizeClothingType(stringValue, l10n);

      case 'computerComponent':
        return localizeComputerComponent(stringValue, l10n);

      case 'consoleBrand':
        return localizeConsoleBrand(stringValue, l10n);

      case 'consoleVariant':
        return localizeConsoleVariant(stringValue, l10n);

      case 'kitchenAppliance':
        return localizeKitchenAppliance(stringValue, l10n);

      case 'whiteGood':
        return localizeWhiteGood(stringValue, l10n);

      case 'fantasyWearType':
        return AllInOneCategoryData.localizeFantasyWearType(stringValue, l10n);

      case 'productType':
        return localizeProductType(stringValue, l10n);

      case 'selectedColor':
        return localizeColorName(stringValue, l10n);

      case 'selectedSize':
      case 'selectedClothingFit':
        return localizeClothingFit(stringValue, l10n);

      case 'selectedGender':
        return localizeGender(stringValue, l10n);

      case 'selectedClothingType':
        return localizeClothingType(stringValue, l10n);

      case 'selectedJewelryType':
        return localizeJewelryType(stringValue, l10n);

      case 'selectedJewelryMaterial':
        return localizeJewelryMaterial(stringValue, l10n);

      case 'selectedComputerComponent':
        return localizeComputerComponent(stringValue, l10n);

      case 'selectedConsoleBrand':
        return localizeConsoleBrand(stringValue, l10n);

      case 'selectedConsoleVariant':
        return localizeConsoleVariant(stringValue, l10n);

      case 'selectedKitchenAppliance':
        return localizeKitchenAppliance(stringValue, l10n);

      case 'selectedWhiteGood':
        return localizeWhiteGood(stringValue, l10n);

      default:
        return stringValue;
    }
  }

  // Individual localization methods for each attribute type

  static String localizeGender(String gender, AppLocalizations l10n) {
    switch (gender) {
      case 'Women':
        return l10n.clothingGenderWomen;
      case 'Men':
        return l10n.clothingGenderMen;
      case 'Unisex':
        return l10n.clothingGenderUnisex;
      default:
        return gender;
    }
  }

  static String localizeClothingSize(String size, AppLocalizations l10n) {
    try {
      return AllInOneCategoryData.localizeClothingSize(size, l10n);
    } catch (e) {
      return size; // Fallback to original if localization fails
    }
  }

  static String localizeClothingFit(String fit, AppLocalizations l10n) {
    try {
      return AllInOneCategoryData.localizeClothingFit(fit, l10n);
    } catch (e) {
      return fit;
    }
  }

  static String localizeClothingType(String type, AppLocalizations l10n) {
    try {
      return AllInOneCategoryData.localizeClothingType(type, l10n);
    } catch (e) {
      return type;
    }
  }

  static String localizeJewelryType(String type, AppLocalizations l10n) {
    switch (type) {
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
        return type;
    }
  }

  static String localizeJewelryMaterial(
      String material, AppLocalizations l10n) {
    switch (material) {
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
        return material;
    }
  }

  static String localizeComputerComponent(
      String component, AppLocalizations l10n) {
    switch (component) {
      case 'CPU':
        return l10n.computerComponentCPU;
      case 'GPU':
        return l10n.computerComponentGPU;
      case 'RAM':
        return l10n.computerComponentRAM;
      case 'Motherboard':
        return l10n.computerComponentMotherboard;
      case 'SSD':
        return l10n.computerComponentSSD;
      case 'HDD':
        return l10n.computerComponentHDD;
      case 'PowerSupply':
        return l10n.computerComponentPowerSupply;
      case 'CoolingSystem':
        return l10n.computerComponentCoolingSystem;
      case 'Case':
        return l10n.computerComponentCase;
      case 'OpticalDrive':
        return l10n.computerComponentOpticalDrive;
      case 'NetworkCard':
        return l10n.computerComponentNetworkCard;
      case 'SoundCard':
        return l10n.computerComponentSoundCard;
      case 'Webcam':
        return l10n.computerComponentWebcam;
      case 'Headset':
        return l10n.computerComponentHeadset;
      default:
        return component;
    }
  }

  static String localizeConsoleBrand(String brand, AppLocalizations l10n) {
    switch (brand) {
      case 'PlayStation':
        return l10n.consoleBrandPlayStation;
      case 'Xbox':
        return l10n.consoleBrandXbox;
      case 'Nintendo':
        return l10n.consoleBrandNintendo;
      case 'PC':
        return l10n.consoleBrandPC;
      case 'Mobile':
        return 'Mobile'; // Add to l10n if needed
      case 'Retro':
        return l10n.consoleBrandRetro;
      default:
        return brand;
    }
  }

  static String localizeConsoleVariant(String variant, AppLocalizations l10n) {
    switch (variant) {
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

      // Mobile variants
      case 'iOS':
        return 'iOS'; // Add to l10n if needed
      case 'Android':
        return 'Android'; // Add to l10n if needed

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
        return variant;
    }
  }

  static String localizeKitchenAppliance(
      String appliance, AppLocalizations l10n) {
    switch (appliance) {
      case 'Microwave':
        return l10n.kitchenApplianceMicrowave;
      case 'CoffeeMachine':
        return l10n.kitchenApplianceCoffeeMachine;
      case 'Blender':
        return l10n.kitchenApplianceBlender;
      case 'FoodProcessor':
        return l10n.kitchenApplianceFoodProcessor;
      case 'Mixer':
        return l10n.kitchenApplianceMixer;
      case 'Toaster':
        return l10n.kitchenApplianceToaster;
      case 'Kettle':
        return l10n.kitchenApplianceKettle;
      case 'RiceCooker':
        return l10n.kitchenApplianceRiceCooker;
      case 'SlowCooker':
        return l10n.kitchenApplianceSlowCooker;
      case 'PressureCooker':
        return l10n.kitchenAppliancePressureCooker;
      case 'AirFryer':
        return l10n.kitchenApplianceAirFryer;
      case 'Juicer':
        return l10n.kitchenApplianceJuicer;
      case 'Grinder':
        return l10n.kitchenApplianceGrinder;
      case 'Oven':
        return l10n.kitchenApplianceOven;
      case 'IceMaker':
        return l10n.kitchenApplianceIceMaker;
      case 'WaterDispenser':
        return l10n.kitchenApplianceWaterDispenser;
      case 'FoodDehydrator':
        return l10n.kitchenApplianceFoodDehydrator;
      case 'Steamer':
        return l10n.kitchenApplianceSteamer;
      case 'Grill':
        return l10n.kitchenApplianceGrill;
      case 'SandwichMaker':
        return l10n.kitchenApplianceSandwichMaker;
      case 'Waffle_Iron':
        return l10n.kitchenApplianceWaffleIron;
      case 'Deep_Fryer':
        return l10n.kitchenApplianceDeepFryer;
      case 'Bread_Maker':
        return l10n.kitchenApplianceBreadMaker;
      case 'Yogurt_Maker':
        return l10n.kitchenApplianceYogurtMaker;
      case 'Ice_Cream_Maker':
        return l10n.kitchenApplianceIceCreamMaker;
      case 'Pasta_Maker':
        return l10n.kitchenAppliancePastaMaker;
      case 'Meat_Grinder':
        return l10n.kitchenApplianceMeatGrinder;
      case 'Can_Opener':
        return l10n.kitchenApplianceCanOpener;
      case 'Knife_Sharpener':
        return l10n.kitchenApplianceKnifeSharpener;
      case 'Scale':
        return l10n.kitchenApplianceScale;
      case 'Timer':
        return l10n.kitchenApplianceTimer;
      default:
        return appliance;
    }
  }

  static String localizeWhiteGood(String whiteGood, AppLocalizations l10n) {
    switch (whiteGood) {
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
        return whiteGood;
    }
  }

  /// Localizes a unified productType value by trying all known type localizers.
  static String localizeProductType(String value, AppLocalizations l10n) {
    // Try each category-specific localizer; return the first non-raw match
    final tryKitchen = localizeKitchenAppliance(value, l10n);
    if (tryKitchen != value) return tryKitchen;

    final tryWhiteGood = localizeWhiteGood(value, l10n);
    if (tryWhiteGood != value) return tryWhiteGood;

    final tryComputer = localizeComputerComponent(value, l10n);
    if (tryComputer != value) return tryComputer;

    final tryJewelry = localizeJewelryType(value, l10n);
    if (tryJewelry != value) return tryJewelry;

    final tryConsole = localizeConsoleBrand(value, l10n);
    if (tryConsole != value) return tryConsole;

    final tryFantasy =
        AllInOneCategoryData.localizeFantasyWearType(value, l10n);
    if (tryFantasy != value) return tryFantasy;

    return value;
  }

  /// Formats color display with localized color names and quantities
  static String formatColorDisplay(
      Map<String, Map<String, dynamic>> selectedColorImages,
      AppLocalizations l10n) {
    if (selectedColorImages.isEmpty) return '';

    final List<String> colorDisplays = [];

    selectedColorImages.forEach((colorName, data) {
      final localizedColorName = localizeColorName(colorName, l10n);

      // Extract quantity from the data map
      dynamic quantityValue;
      quantityValue = data['quantity'];
    
      if (quantityValue != null && quantityValue is int && quantityValue > 0) {
        colorDisplays.add('$localizedColorName: $quantityValue');
      } else if (quantityValue != null) {
        // Handle case where quantity might be a string
        final intQuantity = int.tryParse(quantityValue.toString());
        if (intQuantity != null && intQuantity > 0) {
          colorDisplays.add('$localizedColorName: $intQuantity');
        } else {
          colorDisplays.add(localizedColorName);
        }
      } else {
        colorDisplays.add(localizedColorName);
      }
    });

    return colorDisplays.join(', ');
  }

  static String localizeColorName(String colorName, AppLocalizations l10n) {
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
        return l10n.normal ?? 'Normal'; // Fallback to English name
    }
  }
}
