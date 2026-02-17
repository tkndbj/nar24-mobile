import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('tr')
  ];

  /// No description provided for @andText.
  ///
  /// In tr, this message translates to:
  /// **'ve'**
  String get andText;

  /// No description provided for @buyerCategoryWomen.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get buyerCategoryWomen;

  /// No description provided for @buyerCategoryMen.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get buyerCategoryMen;

  /// No description provided for @buyerSubcategoryFashion.
  ///
  /// In tr, this message translates to:
  /// **'Moda'**
  String get buyerSubcategoryFashion;

  /// No description provided for @buyerSubcategoryShoes.
  ///
  /// In tr, this message translates to:
  /// **'Ayakkabı'**
  String get buyerSubcategoryShoes;

  /// No description provided for @buyerSubcategoryAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Aksesuarlar'**
  String get buyerSubcategoryAccessories;

  /// No description provided for @buyerSubcategoryBags.
  ///
  /// In tr, this message translates to:
  /// **'Çanta & Bavul'**
  String get buyerSubcategoryBags;

  /// No description provided for @buyerSubcategorySelfCare.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Bakım'**
  String get buyerSubcategorySelfCare;

  /// No description provided for @genderFilterWomen.
  ///
  /// In tr, this message translates to:
  /// **'Women\'s'**
  String get genderFilterWomen;

  /// No description provided for @genderFilterMen.
  ///
  /// In tr, this message translates to:
  /// **'Men\'s'**
  String get genderFilterMen;

  /// No description provided for @genderFilterUnisex.
  ///
  /// In tr, this message translates to:
  /// **'Unisex'**
  String get genderFilterUnisex;

  /// No description provided for @categoryClothingFashion.
  ///
  /// In tr, this message translates to:
  /// **'Giyim ve Moda'**
  String get categoryClothingFashion;

  /// No description provided for @categoryFootwear.
  ///
  /// In tr, this message translates to:
  /// **'Ayakkabı'**
  String get categoryFootwear;

  /// No description provided for @categoryAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Aksesuarlar'**
  String get categoryAccessories;

  /// No description provided for @categoryMotherChild.
  ///
  /// In tr, this message translates to:
  /// **'Anne ve Çocuk'**
  String get categoryMotherChild;

  /// No description provided for @categoryHomeFurniture.
  ///
  /// In tr, this message translates to:
  /// **'Ev ve Mobilya'**
  String get categoryHomeFurniture;

  /// No description provided for @categoryBeautyPersonalCare.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik ve Kişisel Bakım'**
  String get categoryBeautyPersonalCare;

  /// No description provided for @subSubcategoryWhiteGoods.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz Eşya'**
  String get subSubcategoryWhiteGoods;

  /// No description provided for @categoryBagsLuggage.
  ///
  /// In tr, this message translates to:
  /// **'Çanta ve Bavul'**
  String get categoryBagsLuggage;

  /// No description provided for @categoryElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik'**
  String get categoryElectronics;

  /// No description provided for @categorySportsOutdoor.
  ///
  /// In tr, this message translates to:
  /// **'Spor ve Outdoor'**
  String get categorySportsOutdoor;

  /// No description provided for @categoryBooksStationeryHobby.
  ///
  /// In tr, this message translates to:
  /// **'Kitap, Kırtasiye ve Hobi'**
  String get categoryBooksStationeryHobby;

  /// No description provided for @categoryToolsHardware.
  ///
  /// In tr, this message translates to:
  /// **'Alet ve Hırdavat'**
  String get categoryToolsHardware;

  /// No description provided for @categoryPetSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Malzemeleri'**
  String get categoryPetSupplies;

  /// No description provided for @categoryAutomotive.
  ///
  /// In tr, this message translates to:
  /// **'Otomotiv'**
  String get categoryAutomotive;

  /// No description provided for @categoryHealthWellness.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık ve Zindelik'**
  String get categoryHealthWellness;

  /// No description provided for @subcategoryDresses.
  ///
  /// In tr, this message translates to:
  /// **'Elbiseler'**
  String get subcategoryDresses;

  /// No description provided for @subcategoryTopsShirts.
  ///
  /// In tr, this message translates to:
  /// **'Üst Giyim'**
  String get subcategoryTopsShirts;

  /// No description provided for @subcategoryBottoms.
  ///
  /// In tr, this message translates to:
  /// **'Alt Giyim'**
  String get subcategoryBottoms;

  /// No description provided for @subcategoryOuterwear.
  ///
  /// In tr, this message translates to:
  /// **'Dış Giyim'**
  String get subcategoryOuterwear;

  /// No description provided for @subcategoryUnderwearSleepwear.
  ///
  /// In tr, this message translates to:
  /// **'İç Giyim ve Pijama'**
  String get subcategoryUnderwearSleepwear;

  /// No description provided for @subcategorySwimwear.
  ///
  /// In tr, this message translates to:
  /// **'Mayo'**
  String get subcategorySwimwear;

  /// No description provided for @subcategoryActivewear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Giyim'**
  String get subcategoryActivewear;

  /// No description provided for @subcategorySuitsFormal.
  ///
  /// In tr, this message translates to:
  /// **'Takım ve Resmi Giyim'**
  String get subcategorySuitsFormal;

  /// No description provided for @subcategoryTraditionalCultural.
  ///
  /// In tr, this message translates to:
  /// **'Geleneksel ve Kültürel Giyim'**
  String get subcategoryTraditionalCultural;

  /// No description provided for @subcategorySneakersAthletic.
  ///
  /// In tr, this message translates to:
  /// **'Spor Ayakkabı'**
  String get subcategorySneakersAthletic;

  /// No description provided for @subcategoryCasualShoes.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Ayakkabı'**
  String get subcategoryCasualShoes;

  /// No description provided for @subcategoryFormalShoes.
  ///
  /// In tr, this message translates to:
  /// **'Resmi Ayakkabı'**
  String get subcategoryFormalShoes;

  /// No description provided for @subcategoryBoots.
  ///
  /// In tr, this message translates to:
  /// **'Bot'**
  String get subcategoryBoots;

  /// No description provided for @subcategorySandalsFlipFlops.
  ///
  /// In tr, this message translates to:
  /// **'Sandalet ve Terlik'**
  String get subcategorySandalsFlipFlops;

  /// No description provided for @subcategorySlippers.
  ///
  /// In tr, this message translates to:
  /// **'Ev Terlikleri'**
  String get subcategorySlippers;

  /// No description provided for @subcategorySpecializedFootwear.
  ///
  /// In tr, this message translates to:
  /// **'Özel Amaçlı Ayakkabı'**
  String get subcategorySpecializedFootwear;

  /// No description provided for @subcategoryJewelry.
  ///
  /// In tr, this message translates to:
  /// **'Mücevher'**
  String get subcategoryJewelry;

  /// No description provided for @subcategoryWatches.
  ///
  /// In tr, this message translates to:
  /// **'Saatler'**
  String get subcategoryWatches;

  /// No description provided for @subcategoryBelts.
  ///
  /// In tr, this message translates to:
  /// **'Kemerler'**
  String get subcategoryBelts;

  /// No description provided for @subcategoryHatsCaps.
  ///
  /// In tr, this message translates to:
  /// **'Şapka ve Bereler'**
  String get subcategoryHatsCaps;

  /// No description provided for @subcategoryScarvesWraps.
  ///
  /// In tr, this message translates to:
  /// **'Atkı ve Şallar'**
  String get subcategoryScarvesWraps;

  /// No description provided for @subcategorySunglassesEyewear.
  ///
  /// In tr, this message translates to:
  /// **'Güneş Gözlükleri ve Gözlük'**
  String get subcategorySunglassesEyewear;

  /// No description provided for @subcategoryGloves.
  ///
  /// In tr, this message translates to:
  /// **'Eldivenler'**
  String get subcategoryGloves;

  /// No description provided for @subcategoryHairAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Saç Aksesuarları'**
  String get subcategoryHairAccessories;

  /// No description provided for @subcategoryOtherAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Diğer Aksesuarlar'**
  String get subcategoryOtherAccessories;

  /// No description provided for @subcategoryBabyClothing.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Giyim'**
  String get subcategoryBabyClothing;

  /// No description provided for @subcategoryKidsClothing.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Giyim'**
  String get subcategoryKidsClothing;

  /// No description provided for @subcategoryKidsFootwear.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Ayakkabı'**
  String get subcategoryKidsFootwear;

  /// No description provided for @subcategoryToysGames.
  ///
  /// In tr, this message translates to:
  /// **'Oyuncak ve Oyunlar'**
  String get subcategoryToysGames;

  /// No description provided for @subcategoryBabyCare.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Bakımı'**
  String get subcategoryBabyCare;

  /// No description provided for @subcategoryMaternity.
  ///
  /// In tr, this message translates to:
  /// **'Hamilelik'**
  String get subcategoryMaternity;

  /// No description provided for @subcategoryStrollersCarSeats.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Arabası ve Oto Koltuğu'**
  String get subcategoryStrollersCarSeats;

  /// No description provided for @subcategoryFeedingNursing.
  ///
  /// In tr, this message translates to:
  /// **'Beslenme ve Emzirme'**
  String get subcategoryFeedingNursing;

  /// No description provided for @subcategorySafetySecurity.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik'**
  String get subcategorySafetySecurity;

  /// No description provided for @subcategoryEducational.
  ///
  /// In tr, this message translates to:
  /// **'Eğitici'**
  String get subcategoryEducational;

  /// No description provided for @subcategoryLivingRoomFurniture.
  ///
  /// In tr, this message translates to:
  /// **'Oturma Odası Mobilyası'**
  String get subcategoryLivingRoomFurniture;

  /// No description provided for @subcategoryBedroomFurniture.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Odası Mobilyası'**
  String get subcategoryBedroomFurniture;

  /// No description provided for @subcategoryKitchenDining.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak ve Yemek Odası'**
  String get subcategoryKitchenDining;

  /// No description provided for @subcategoryBathroom.
  ///
  /// In tr, this message translates to:
  /// **'Banyo'**
  String get subcategoryBathroom;

  /// No description provided for @subcategoryHomeDecor.
  ///
  /// In tr, this message translates to:
  /// **'Ev Dekorasyonu'**
  String get subcategoryHomeDecor;

  /// No description provided for @subcategoryLighting.
  ///
  /// In tr, this message translates to:
  /// **'Aydınlatma'**
  String get subcategoryLighting;

  /// No description provided for @subcategoryStorageOrganization.
  ///
  /// In tr, this message translates to:
  /// **'Saklama ve Organizasyon'**
  String get subcategoryStorageOrganization;

  /// No description provided for @subcategoryTextilesSoftFurnishing.
  ///
  /// In tr, this message translates to:
  /// **'Tekstil ve Yumuşak Mobilya'**
  String get subcategoryTextilesSoftFurnishing;

  /// No description provided for @subcategoryGardenOutdoor.
  ///
  /// In tr, this message translates to:
  /// **'Bahçe ve Outdoor'**
  String get subcategoryGardenOutdoor;

  /// No description provided for @subcategorySkincare.
  ///
  /// In tr, this message translates to:
  /// **'Cilt Bakımı'**
  String get subcategorySkincare;

  /// No description provided for @subcategoryMakeup.
  ///
  /// In tr, this message translates to:
  /// **'Makyaj'**
  String get subcategoryMakeup;

  /// No description provided for @subcategoryHaircare.
  ///
  /// In tr, this message translates to:
  /// **'Saç Bakımı'**
  String get subcategoryHaircare;

  /// No description provided for @subcategoryFragrances.
  ///
  /// In tr, this message translates to:
  /// **'Parfüm'**
  String get subcategoryFragrances;

  /// No description provided for @subcategoryPersonalHygiene.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Hijyen'**
  String get subcategoryPersonalHygiene;

  /// No description provided for @subcategoryNailCare.
  ///
  /// In tr, this message translates to:
  /// **'Tırnak Bakımı'**
  String get subcategoryNailCare;

  /// No description provided for @subcategoryBodyCare.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Bakımı'**
  String get subcategoryBodyCare;

  /// No description provided for @subcategoryOralCare.
  ///
  /// In tr, this message translates to:
  /// **'Ağız Bakımı'**
  String get subcategoryOralCare;

  /// No description provided for @subcategoryBeautyToolsAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Araçları ve Aksesuarları'**
  String get subcategoryBeautyToolsAccessories;

  /// No description provided for @subcategoryHandbags.
  ///
  /// In tr, this message translates to:
  /// **'El Çantaları'**
  String get subcategoryHandbags;

  /// No description provided for @subcategoryBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Sırt Çantaları'**
  String get subcategoryBackpacks;

  /// No description provided for @subcategoryTravelLuggage.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Bavulları'**
  String get subcategoryTravelLuggage;

  /// No description provided for @subcategoryBriefcasesBusinessBags.
  ///
  /// In tr, this message translates to:
  /// **'Evrak Çantası ve İş Çantaları'**
  String get subcategoryBriefcasesBusinessBags;

  /// No description provided for @subcategorySportsGymBags.
  ///
  /// In tr, this message translates to:
  /// **'Spor ve Jimnastik Çantaları'**
  String get subcategorySportsGymBags;

  /// No description provided for @subcategoryWalletsSmallAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Cüzdan ve Küçük Aksesuarlar'**
  String get subcategoryWalletsSmallAccessories;

  /// No description provided for @subcategorySpecialtyBags.
  ///
  /// In tr, this message translates to:
  /// **'Özel Amaçlı Çantalar'**
  String get subcategorySpecialtyBags;

  /// No description provided for @subcategorySmartphonesAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Telefon ve Aksesuarları'**
  String get subcategorySmartphonesAccessories;

  /// No description provided for @subcategoryComputersLaptops.
  ///
  /// In tr, this message translates to:
  /// **'Bilgisayar ve Laptop'**
  String get subcategoryComputersLaptops;

  /// No description provided for @subcategoryTVsHomeEntertainment.
  ///
  /// In tr, this message translates to:
  /// **'TV ve Ev Eğlence Sistemleri'**
  String get subcategoryTVsHomeEntertainment;

  /// No description provided for @subcategoryAudioEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Ses Sistemleri'**
  String get subcategoryAudioEquipment;

  /// No description provided for @subcategoryGaming.
  ///
  /// In tr, this message translates to:
  /// **'Oyun'**
  String get subcategoryGaming;

  /// No description provided for @subcategorySmartHomeIoT.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Ev ve IoT'**
  String get subcategorySmartHomeIoT;

  /// No description provided for @subcategoryCamerasPhotography.
  ///
  /// In tr, this message translates to:
  /// **'Kamera ve Fotoğrafçılık'**
  String get subcategoryCamerasPhotography;

  /// No description provided for @subcategoryWearableTech.
  ///
  /// In tr, this message translates to:
  /// **'Giyilebilir Teknoloji'**
  String get subcategoryWearableTech;

  /// No description provided for @subcategoryHomeAppliances.
  ///
  /// In tr, this message translates to:
  /// **'Ev Aletleri'**
  String get subcategoryHomeAppliances;

  /// No description provided for @subcategoryPersonalCareElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Bakım Elektroniği'**
  String get subcategoryPersonalCareElectronics;

  /// No description provided for @subcategoryFitnessExercise.
  ///
  /// In tr, this message translates to:
  /// **'Fitness ve Egzersiz'**
  String get subcategoryFitnessExercise;

  /// No description provided for @subcategorySports.
  ///
  /// In tr, this message translates to:
  /// **'Sporlar'**
  String get subcategorySports;

  /// No description provided for @subcategoryWaterSports.
  ///
  /// In tr, this message translates to:
  /// **'Su Sporları'**
  String get subcategoryWaterSports;

  /// No description provided for @subcategoryOutdoorCamping.
  ///
  /// In tr, this message translates to:
  /// **'Outdoor ve Kamp'**
  String get subcategoryOutdoorCamping;

  /// No description provided for @subcategoryWinterSports.
  ///
  /// In tr, this message translates to:
  /// **'Kış Sporları'**
  String get subcategoryWinterSports;

  /// No description provided for @subcategoryCycling.
  ///
  /// In tr, this message translates to:
  /// **'Bisiklet'**
  String get subcategoryCycling;

  /// No description provided for @subcategoryRunningAthletics.
  ///
  /// In tr, this message translates to:
  /// **'Koşu ve Atletizm'**
  String get subcategoryRunningAthletics;

  /// No description provided for @subcategorySportsAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Spor Aksesuarları'**
  String get subcategorySportsAccessories;

  /// No description provided for @subcategorySportswear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Giyim'**
  String get subcategorySportswear;

  /// No description provided for @subcategoryBooksLiterature.
  ///
  /// In tr, this message translates to:
  /// **'Kitap ve Edebiyat'**
  String get subcategoryBooksLiterature;

  /// No description provided for @subcategoryOfficeSchoolSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Ofis ve Okul Malzemeleri'**
  String get subcategoryOfficeSchoolSupplies;

  /// No description provided for @subcategoryArtCraftSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Sanat ve El Sanatları Malzemeleri'**
  String get subcategoryArtCraftSupplies;

  /// No description provided for @subcategoryWritingInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Yazı Araçları'**
  String get subcategoryWritingInstruments;

  /// No description provided for @subcategoryPaperProducts.
  ///
  /// In tr, this message translates to:
  /// **'Kağıt Ürünleri'**
  String get subcategoryPaperProducts;

  /// No description provided for @subcategoryEducationalMaterials.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Materyalleri'**
  String get subcategoryEducationalMaterials;

  /// No description provided for @subcategoryHobbiesCollections.
  ///
  /// In tr, this message translates to:
  /// **'Hobiler ve Koleksiyonlar'**
  String get subcategoryHobbiesCollections;

  /// No description provided for @subcategoryMusicalInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Müzik Aletleri'**
  String get subcategoryMusicalInstruments;

  /// No description provided for @subcategoryHandTools.
  ///
  /// In tr, this message translates to:
  /// **'El Aletleri'**
  String get subcategoryHandTools;

  /// No description provided for @subcategoryPowerTools.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Aletler'**
  String get subcategoryPowerTools;

  /// No description provided for @subcategoryHardwareFasteners.
  ///
  /// In tr, this message translates to:
  /// **'Hırdavat ve Bağlantı Elemanları'**
  String get subcategoryHardwareFasteners;

  /// No description provided for @subcategoryElectricalSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Elektrik Malzemeleri'**
  String get subcategoryElectricalSupplies;

  /// No description provided for @subcategoryPlumbingSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Tesisatçılık Malzemeleri'**
  String get subcategoryPlumbingSupplies;

  /// No description provided for @subcategoryBuildingMaterials.
  ///
  /// In tr, this message translates to:
  /// **'Yapı Malzemeleri'**
  String get subcategoryBuildingMaterials;

  /// No description provided for @subcategorySafetyEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Ekipmanları'**
  String get subcategorySafetyEquipment;

  /// No description provided for @subcategoryMeasuringTools.
  ///
  /// In tr, this message translates to:
  /// **'Ölçüm Aletleri'**
  String get subcategoryMeasuringTools;

  /// No description provided for @subcategoryToolStorage.
  ///
  /// In tr, this message translates to:
  /// **'Alet Saklama'**
  String get subcategoryToolStorage;

  /// No description provided for @subcategoryDogSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Malzemeleri'**
  String get subcategoryDogSupplies;

  /// No description provided for @subcategoryCatSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Malzemeleri'**
  String get subcategoryCatSupplies;

  /// No description provided for @subcategoryBirdSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Malzemeleri'**
  String get subcategoryBirdSupplies;

  /// No description provided for @subcategoryFishAquarium.
  ///
  /// In tr, this message translates to:
  /// **'Balık ve Akvaryum'**
  String get subcategoryFishAquarium;

  /// No description provided for @subcategorySmallAnimalSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Küçük Hayvan Malzemeleri'**
  String get subcategorySmallAnimalSupplies;

  /// No description provided for @subcategoryPetFoodTreats.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Yemi ve Ödülleri'**
  String get subcategoryPetFoodTreats;

  /// No description provided for @subcategoryPetCareHealth.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Bakımı ve Sağlığı'**
  String get subcategoryPetCareHealth;

  /// No description provided for @subcategoryPetAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Aksesuarları'**
  String get subcategoryPetAccessories;

  /// No description provided for @subcategoryPetTraining.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Eğitimi'**
  String get subcategoryPetTraining;

  /// No description provided for @subcategoryCarPartsComponents.
  ///
  /// In tr, this message translates to:
  /// **'Araba Parçaları ve Bileşenleri'**
  String get subcategoryCarPartsComponents;

  /// No description provided for @subcategoryCarElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Araba Elektroniği'**
  String get subcategoryCarElectronics;

  /// No description provided for @subcategoryCarCareMaintenance.
  ///
  /// In tr, this message translates to:
  /// **'Araba Bakımı ve Onarımı'**
  String get subcategoryCarCareMaintenance;

  /// No description provided for @subcategoryTiresWheels.
  ///
  /// In tr, this message translates to:
  /// **'Lastik ve Jantlar'**
  String get subcategoryTiresWheels;

  /// No description provided for @subcategoryInteriorAccessories.
  ///
  /// In tr, this message translates to:
  /// **'İç Aksesuar'**
  String get subcategoryInteriorAccessories;

  /// No description provided for @subcategoryExteriorAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Dış Aksesuar'**
  String get subcategoryExteriorAccessories;

  /// No description provided for @subcategoryToolsEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Araçlar ve Ekipmanlar'**
  String get subcategoryToolsEquipment;

  /// No description provided for @subcategoryMotorcycleParts.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Parçaları'**
  String get subcategoryMotorcycleParts;

  /// No description provided for @subcategoryVitaminsSupplements.
  ///
  /// In tr, this message translates to:
  /// **'Vitamin ve Takviyeler'**
  String get subcategoryVitaminsSupplements;

  /// No description provided for @subcategoryMedicalEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Tıbbi Cihazlar'**
  String get subcategoryMedicalEquipment;

  /// No description provided for @subcategoryFirstAidSafety.
  ///
  /// In tr, this message translates to:
  /// **'İlk Yardım ve Güvenlik'**
  String get subcategoryFirstAidSafety;

  /// No description provided for @subcategoryFitnessExerciseEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Fitness ve Egzersiz Ekipmanları'**
  String get subcategoryFitnessExerciseEquipment;

  /// No description provided for @subcategoryHealthMonitoring.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık Takibi'**
  String get subcategoryHealthMonitoring;

  /// No description provided for @subcategoryMobilityDailyLiving.
  ///
  /// In tr, this message translates to:
  /// **'Mobilite ve Günlük Yaşam'**
  String get subcategoryMobilityDailyLiving;

  /// No description provided for @subcategoryAlternativeMedicine.
  ///
  /// In tr, this message translates to:
  /// **'Alternatif Tıp'**
  String get subcategoryAlternativeMedicine;

  /// No description provided for @subcategoryPersonalCare.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Bakım'**
  String get subcategoryPersonalCare;

  /// No description provided for @subSubcategoryCasualDresses.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Elbiseler'**
  String get subSubcategoryCasualDresses;

  /// No description provided for @subSubcategoryFormalDresses.
  ///
  /// In tr, this message translates to:
  /// **'Resmi Elbiseler'**
  String get subSubcategoryFormalDresses;

  /// No description provided for @subSubcategoryEveningGowns.
  ///
  /// In tr, this message translates to:
  /// **'Gece Elbiseleri'**
  String get subSubcategoryEveningGowns;

  /// No description provided for @subSubcategoryCocktailDresses.
  ///
  /// In tr, this message translates to:
  /// **'Kokteyl Elbiseleri'**
  String get subSubcategoryCocktailDresses;

  /// No description provided for @subSubcategoryMaxiDresses.
  ///
  /// In tr, this message translates to:
  /// **'Maksi Elbiseler'**
  String get subSubcategoryMaxiDresses;

  /// No description provided for @subSubcategoryMiniDresses.
  ///
  /// In tr, this message translates to:
  /// **'Mini Elbiseler'**
  String get subSubcategoryMiniDresses;

  /// No description provided for @subSubcategoryMidiDresses.
  ///
  /// In tr, this message translates to:
  /// **'Midi Elbiseler'**
  String get subSubcategoryMidiDresses;

  /// No description provided for @subSubcategoryWeddingDresses.
  ///
  /// In tr, this message translates to:
  /// **'Gelinlikler'**
  String get subSubcategoryWeddingDresses;

  /// No description provided for @subSubcategorySundresses.
  ///
  /// In tr, this message translates to:
  /// **'Yazlık Elbiseler'**
  String get subSubcategorySundresses;

  /// No description provided for @subSubcategoryTShirts.
  ///
  /// In tr, this message translates to:
  /// **'Tişörtler'**
  String get subSubcategoryTShirts;

  /// No description provided for @subSubcategoryShirts.
  ///
  /// In tr, this message translates to:
  /// **'Gömlekler'**
  String get subSubcategoryShirts;

  /// No description provided for @subSubcategoryBlouses.
  ///
  /// In tr, this message translates to:
  /// **'Bluzlar'**
  String get subSubcategoryBlouses;

  /// No description provided for @subSubcategoryTankTops.
  ///
  /// In tr, this message translates to:
  /// **'Atlet'**
  String get subSubcategoryTankTops;

  /// No description provided for @subSubcategoryPoloShirts.
  ///
  /// In tr, this message translates to:
  /// **'Polo Tişörtler'**
  String get subSubcategoryPoloShirts;

  /// No description provided for @subSubcategoryCropTops.
  ///
  /// In tr, this message translates to:
  /// **'Kısa Üstler'**
  String get subSubcategoryCropTops;

  /// No description provided for @subSubcategoryTunics.
  ///
  /// In tr, this message translates to:
  /// **'Tunikler'**
  String get subSubcategoryTunics;

  /// No description provided for @subSubcategoryHoodies.
  ///
  /// In tr, this message translates to:
  /// **'Kapüşonlular'**
  String get subSubcategoryHoodies;

  /// No description provided for @subSubcategorySweatshirts.
  ///
  /// In tr, this message translates to:
  /// **'Sweatshirtler'**
  String get subSubcategorySweatshirts;

  /// No description provided for @subSubcategoryJeans.
  ///
  /// In tr, this message translates to:
  /// **'Kotlar'**
  String get subSubcategoryJeans;

  /// No description provided for @subSubcategoryPants.
  ///
  /// In tr, this message translates to:
  /// **'Pantolonlar'**
  String get subSubcategoryPants;

  /// No description provided for @subSubcategoryShorts.
  ///
  /// In tr, this message translates to:
  /// **'Şortlar'**
  String get subSubcategoryShorts;

  /// No description provided for @subSubcategorySkirts.
  ///
  /// In tr, this message translates to:
  /// **'Etekler'**
  String get subSubcategorySkirts;

  /// No description provided for @subSubcategoryLeggings.
  ///
  /// In tr, this message translates to:
  /// **'Taytlar'**
  String get subSubcategoryLeggings;

  /// No description provided for @subSubcategoryJoggers.
  ///
  /// In tr, this message translates to:
  /// **'Eşofman Altları'**
  String get subSubcategoryJoggers;

  /// No description provided for @subSubcategoryCapris.
  ///
  /// In tr, this message translates to:
  /// **'Kapri'**
  String get subSubcategoryCapris;

  /// No description provided for @subSubcategoryCulottes.
  ///
  /// In tr, this message translates to:
  /// **'Bol Pantolonlar'**
  String get subSubcategoryCulottes;

  /// No description provided for @subSubcategoryFantasy.
  ///
  /// In tr, this message translates to:
  /// **'Fantezi Giyim'**
  String get subSubcategoryFantasy;

  /// No description provided for @subSubcategoryJackets.
  ///
  /// In tr, this message translates to:
  /// **'Ceketler'**
  String get subSubcategoryJackets;

  /// No description provided for @subSubcategoryCoats.
  ///
  /// In tr, this message translates to:
  /// **'Paltolar'**
  String get subSubcategoryCoats;

  /// No description provided for @subSubcategoryBlazers.
  ///
  /// In tr, this message translates to:
  /// **'Blazerlar'**
  String get subSubcategoryBlazers;

  /// No description provided for @subSubcategoryCardigans.
  ///
  /// In tr, this message translates to:
  /// **'Hırkalar'**
  String get subSubcategoryCardigans;

  /// No description provided for @subSubcategorySweaters.
  ///
  /// In tr, this message translates to:
  /// **'Kazaklar'**
  String get subSubcategorySweaters;

  /// No description provided for @subSubcategoryVests.
  ///
  /// In tr, this message translates to:
  /// **'Yelekler'**
  String get subSubcategoryVests;

  /// No description provided for @subSubcategoryParkas.
  ///
  /// In tr, this message translates to:
  /// **'Parkalar'**
  String get subSubcategoryParkas;

  /// No description provided for @subSubcategoryTrenchCoats.
  ///
  /// In tr, this message translates to:
  /// **'Trençkotlar'**
  String get subSubcategoryTrenchCoats;

  /// No description provided for @subSubcategoryWindbreakers.
  ///
  /// In tr, this message translates to:
  /// **'Rüzgarlıklar'**
  String get subSubcategoryWindbreakers;

  /// No description provided for @subSubcategoryBras.
  ///
  /// In tr, this message translates to:
  /// **'Sütyenler'**
  String get subSubcategoryBras;

  /// No description provided for @subSubcategoryPanties.
  ///
  /// In tr, this message translates to:
  /// **'Külotlar'**
  String get subSubcategoryPanties;

  /// No description provided for @subSubcategoryBoxers.
  ///
  /// In tr, this message translates to:
  /// **'Boxer'**
  String get subSubcategoryBoxers;

  /// No description provided for @subSubcategoryBriefs.
  ///
  /// In tr, this message translates to:
  /// **'Slip'**
  String get subSubcategoryBriefs;

  /// No description provided for @subSubcategoryUndershirts.
  ///
  /// In tr, this message translates to:
  /// **'Fanila'**
  String get subSubcategoryUndershirts;

  /// No description provided for @subSubcategorySleepwear.
  ///
  /// In tr, this message translates to:
  /// **'Pijama'**
  String get subSubcategorySleepwear;

  /// No description provided for @subSubcategoryPajamas.
  ///
  /// In tr, this message translates to:
  /// **'Pijama Takımları'**
  String get subSubcategoryPajamas;

  /// No description provided for @subSubcategoryNightgowns.
  ///
  /// In tr, this message translates to:
  /// **'Gecelikler'**
  String get subSubcategoryNightgowns;

  /// No description provided for @subSubcategoryRobes.
  ///
  /// In tr, this message translates to:
  /// **'Sabahlıklar'**
  String get subSubcategoryRobes;

  /// No description provided for @subSubcategorySocks.
  ///
  /// In tr, this message translates to:
  /// **'Çoraplar'**
  String get subSubcategorySocks;

  /// No description provided for @subSubcategoryTights.
  ///
  /// In tr, this message translates to:
  /// **'Külotlu Çoraplar'**
  String get subSubcategoryTights;

  /// No description provided for @subSubcategoryBikinis.
  ///
  /// In tr, this message translates to:
  /// **'Bikiniler'**
  String get subSubcategoryBikinis;

  /// No description provided for @subSubcategoryOnePieceSwimsuits.
  ///
  /// In tr, this message translates to:
  /// **'Tek Parça Mayolar'**
  String get subSubcategoryOnePieceSwimsuits;

  /// No description provided for @subSubcategorySwimShorts.
  ///
  /// In tr, this message translates to:
  /// **'Mayo Şortu'**
  String get subSubcategorySwimShorts;

  /// No description provided for @subSubcategoryBoardshorts.
  ///
  /// In tr, this message translates to:
  /// **'Sörf Şortu'**
  String get subSubcategoryBoardshorts;

  /// No description provided for @subSubcategoryCoverUps.
  ///
  /// In tr, this message translates to:
  /// **'Pareo'**
  String get subSubcategoryCoverUps;

  /// No description provided for @subSubcategoryRashguards.
  ///
  /// In tr, this message translates to:
  /// **'Rashguard'**
  String get subSubcategoryRashguards;

  /// No description provided for @subSubcategorySportsBras.
  ///
  /// In tr, this message translates to:
  /// **'Spor Sütyenleri'**
  String get subSubcategorySportsBras;

  /// No description provided for @subSubcategoryAthleticTops.
  ///
  /// In tr, this message translates to:
  /// **'Spor Üstleri'**
  String get subSubcategoryAthleticTops;

  /// No description provided for @subSubcategoryAthleticBottoms.
  ///
  /// In tr, this message translates to:
  /// **'Spor Altları'**
  String get subSubcategoryAthleticBottoms;

  /// No description provided for @subSubcategoryTracksuits.
  ///
  /// In tr, this message translates to:
  /// **'Eşofman Takımları'**
  String get subSubcategoryTracksuits;

  /// No description provided for @subSubcategoryYogaWear.
  ///
  /// In tr, this message translates to:
  /// **'Yoga Giyimi'**
  String get subSubcategoryYogaWear;

  /// No description provided for @subSubcategoryRunningGear.
  ///
  /// In tr, this message translates to:
  /// **'Koşu Giyimi'**
  String get subSubcategoryRunningGear;

  /// No description provided for @subSubcategoryGymWear.
  ///
  /// In tr, this message translates to:
  /// **'Jimnastik Giyimi'**
  String get subSubcategoryGymWear;

  /// No description provided for @subSubcategoryBusinessSuits.
  ///
  /// In tr, this message translates to:
  /// **'İş Takımları'**
  String get subSubcategoryBusinessSuits;

  /// No description provided for @subSubcategoryTuxedos.
  ///
  /// In tr, this message translates to:
  /// **'Smokinler'**
  String get subSubcategoryTuxedos;

  /// No description provided for @subSubcategoryFormalShirts.
  ///
  /// In tr, this message translates to:
  /// **'Resmi Gömlekler'**
  String get subSubcategoryFormalShirts;

  /// No description provided for @subSubcategoryDressPants.
  ///
  /// In tr, this message translates to:
  /// **'Kumaş Pantolonlar'**
  String get subSubcategoryDressPants;

  /// No description provided for @subSubcategoryWaistcoats.
  ///
  /// In tr, this message translates to:
  /// **'Yelekler'**
  String get subSubcategoryWaistcoats;

  /// No description provided for @subSubcategoryBowTies.
  ///
  /// In tr, this message translates to:
  /// **'Papyonlar'**
  String get subSubcategoryBowTies;

  /// No description provided for @subSubcategoryCufflinks.
  ///
  /// In tr, this message translates to:
  /// **'Kol Düğmeleri'**
  String get subSubcategoryCufflinks;

  /// No description provided for @subSubcategoryEthnicWear.
  ///
  /// In tr, this message translates to:
  /// **'Etnik Giyim'**
  String get subSubcategoryEthnicWear;

  /// No description provided for @subSubcategoryCulturalCostumes.
  ///
  /// In tr, this message translates to:
  /// **'Kültürel Kostümler'**
  String get subSubcategoryCulturalCostumes;

  /// No description provided for @subSubcategoryTraditionalDresses.
  ///
  /// In tr, this message translates to:
  /// **'Geleneksel Elbiseler'**
  String get subSubcategoryTraditionalDresses;

  /// No description provided for @subSubcategoryCeremonialClothing.
  ///
  /// In tr, this message translates to:
  /// **'Tören Giysileri'**
  String get subSubcategoryCeremonialClothing;

  /// No description provided for @subSubcategoryRunningShoes.
  ///
  /// In tr, this message translates to:
  /// **'Koşu Ayakkabıları'**
  String get subSubcategoryRunningShoes;

  /// No description provided for @subSubcategoryBasketballShoes.
  ///
  /// In tr, this message translates to:
  /// **'Basketbol Ayakkabıları'**
  String get subSubcategoryBasketballShoes;

  /// No description provided for @subSubcategoryTrainingShoes.
  ///
  /// In tr, this message translates to:
  /// **'Antrenman Ayakkabıları'**
  String get subSubcategoryTrainingShoes;

  /// No description provided for @subSubcategoryCasualSneakers.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Spor Ayakkabı'**
  String get subSubcategoryCasualSneakers;

  /// No description provided for @subSubcategorySkateboardShoes.
  ///
  /// In tr, this message translates to:
  /// **'Kaykay Ayakkabıları'**
  String get subSubcategorySkateboardShoes;

  /// No description provided for @subSubcategoryTennisShoes.
  ///
  /// In tr, this message translates to:
  /// **'Tenis Ayakkabıları'**
  String get subSubcategoryTennisShoes;

  /// No description provided for @subSubcategoryWalkingShoes.
  ///
  /// In tr, this message translates to:
  /// **'Yürüyüş Ayakkabıları'**
  String get subSubcategoryWalkingShoes;

  /// No description provided for @subSubcategoryLoafers.
  ///
  /// In tr, this message translates to:
  /// **'Loaferlar'**
  String get subSubcategoryLoafers;

  /// No description provided for @subSubcategoryBoatShoes.
  ///
  /// In tr, this message translates to:
  /// **'Tekne Ayakkabıları'**
  String get subSubcategoryBoatShoes;

  /// No description provided for @subSubcategoryCanvasShoes.
  ///
  /// In tr, this message translates to:
  /// **'Kanvas Ayakkabılar'**
  String get subSubcategoryCanvasShoes;

  /// No description provided for @subSubcategorySlipOnShoes.
  ///
  /// In tr, this message translates to:
  /// **'Bağcıksız Ayakkabılar'**
  String get subSubcategorySlipOnShoes;

  /// No description provided for @subSubcategoryEspadrilles.
  ///
  /// In tr, this message translates to:
  /// **'Espadril'**
  String get subSubcategoryEspadrilles;

  /// No description provided for @subSubcategoryMoccasins.
  ///
  /// In tr, this message translates to:
  /// **'Mokasenler'**
  String get subSubcategoryMoccasins;

  /// No description provided for @subSubcategoryDressShoes.
  ///
  /// In tr, this message translates to:
  /// **'Klasik Ayakkabılar'**
  String get subSubcategoryDressShoes;

  /// No description provided for @subSubcategoryOxfordShoes.
  ///
  /// In tr, this message translates to:
  /// **'Oxford Ayakkabılar'**
  String get subSubcategoryOxfordShoes;

  /// No description provided for @subSubcategoryDerbyShoes.
  ///
  /// In tr, this message translates to:
  /// **'Derby Ayakkabılar'**
  String get subSubcategoryDerbyShoes;

  /// No description provided for @subSubcategoryMonkStrapShoes.
  ///
  /// In tr, this message translates to:
  /// **'Monk Strap Ayakkabılar'**
  String get subSubcategoryMonkStrapShoes;

  /// No description provided for @subSubcategoryPumps.
  ///
  /// In tr, this message translates to:
  /// **'Topuklu Ayakkabılar'**
  String get subSubcategoryPumps;

  /// No description provided for @subSubcategoryHighHeels.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek Topuklu'**
  String get subSubcategoryHighHeels;

  /// No description provided for @subSubcategoryFlats.
  ///
  /// In tr, this message translates to:
  /// **'Babet'**
  String get subSubcategoryFlats;

  /// No description provided for @subSubcategoryAnkleBoots.
  ///
  /// In tr, this message translates to:
  /// **'Bot'**
  String get subSubcategoryAnkleBoots;

  /// No description provided for @subSubcategoryKneeHighBoots.
  ///
  /// In tr, this message translates to:
  /// **'Diz Üstü Çizmeler'**
  String get subSubcategoryKneeHighBoots;

  /// No description provided for @subSubcategoryCombatBoots.
  ///
  /// In tr, this message translates to:
  /// **'Savaş Botları'**
  String get subSubcategoryCombatBoots;

  /// No description provided for @subSubcategoryChelseaBoots.
  ///
  /// In tr, this message translates to:
  /// **'Chelsea Botları'**
  String get subSubcategoryChelseaBoots;

  /// No description provided for @subSubcategoryWorkBoots.
  ///
  /// In tr, this message translates to:
  /// **'İş Botları'**
  String get subSubcategoryWorkBoots;

  /// No description provided for @subSubcategoryHikingBoots.
  ///
  /// In tr, this message translates to:
  /// **'Trekking Botları'**
  String get subSubcategoryHikingBoots;

  /// No description provided for @subSubcategoryRainBoots.
  ///
  /// In tr, this message translates to:
  /// **'Yağmur Çizmeleri'**
  String get subSubcategoryRainBoots;

  /// No description provided for @subSubcategorySnowBoots.
  ///
  /// In tr, this message translates to:
  /// **'Kar Çizmeleri'**
  String get subSubcategorySnowBoots;

  /// No description provided for @subSubcategoryFlipFlops.
  ///
  /// In tr, this message translates to:
  /// **'Parmak Arası Terlikler'**
  String get subSubcategoryFlipFlops;

  /// No description provided for @subSubcategoryFlatSandals.
  ///
  /// In tr, this message translates to:
  /// **'Düz Sandaletler'**
  String get subSubcategoryFlatSandals;

  /// No description provided for @subSubcategoryHeeledSandals.
  ///
  /// In tr, this message translates to:
  /// **'Topuklu Sandaletler'**
  String get subSubcategoryHeeledSandals;

  /// No description provided for @subSubcategorySportSandals.
  ///
  /// In tr, this message translates to:
  /// **'Spor Sandaletleri'**
  String get subSubcategorySportSandals;

  /// No description provided for @subSubcategorySlides.
  ///
  /// In tr, this message translates to:
  /// **'Terlikler'**
  String get subSubcategorySlides;

  /// No description provided for @subSubcategoryGladiatorSandals.
  ///
  /// In tr, this message translates to:
  /// **'Gladyatör Sandaletleri'**
  String get subSubcategoryGladiatorSandals;

  /// No description provided for @subSubcategoryHouseSlippers.
  ///
  /// In tr, this message translates to:
  /// **'Ev Terlikleri'**
  String get subSubcategoryHouseSlippers;

  /// No description provided for @subSubcategoryBedroomSlippers.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Odası Terlikleri'**
  String get subSubcategoryBedroomSlippers;

  /// No description provided for @subSubcategoryMoccasinSlippers.
  ///
  /// In tr, this message translates to:
  /// **'Mokasine Terlikler'**
  String get subSubcategoryMoccasinSlippers;

  /// No description provided for @subSubcategorySlipperBoots.
  ///
  /// In tr, this message translates to:
  /// **'Terlik Botlar'**
  String get subSubcategorySlipperBoots;

  /// No description provided for @subSubcategorySafetyShoes.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Ayakkabıları'**
  String get subSubcategorySafetyShoes;

  /// No description provided for @subSubcategoryMedicalShoes.
  ///
  /// In tr, this message translates to:
  /// **'Medikal Ayakkabılar'**
  String get subSubcategoryMedicalShoes;

  /// No description provided for @subSubcategoryDanceShoes.
  ///
  /// In tr, this message translates to:
  /// **'Dans Ayakkabıları'**
  String get subSubcategoryDanceShoes;

  /// No description provided for @subSubcategoryCleats.
  ///
  /// In tr, this message translates to:
  /// **'Kramponlar'**
  String get subSubcategoryCleats;

  /// No description provided for @subSubcategoryClimbingShoes.
  ///
  /// In tr, this message translates to:
  /// **'Tırmanış Ayakkabıları'**
  String get subSubcategoryClimbingShoes;

  /// No description provided for @subSubcategoryNecklaces.
  ///
  /// In tr, this message translates to:
  /// **'Kolyeler'**
  String get subSubcategoryNecklaces;

  /// No description provided for @subSubcategoryEarrings.
  ///
  /// In tr, this message translates to:
  /// **'Küpeler'**
  String get subSubcategoryEarrings;

  /// No description provided for @subSubcategoryRings.
  ///
  /// In tr, this message translates to:
  /// **'Yüzükler'**
  String get subSubcategoryRings;

  /// No description provided for @subSubcategoryBracelets.
  ///
  /// In tr, this message translates to:
  /// **'Bilezikler'**
  String get subSubcategoryBracelets;

  /// No description provided for @subSubcategoryAnklets.
  ///
  /// In tr, this message translates to:
  /// **'Halhallar'**
  String get subSubcategoryAnklets;

  /// No description provided for @subSubcategoryBrooches.
  ///
  /// In tr, this message translates to:
  /// **'Broşlar'**
  String get subSubcategoryBrooches;

  /// No description provided for @subSubcategoryJewelrySets.
  ///
  /// In tr, this message translates to:
  /// **'Mücevher Setleri'**
  String get subSubcategoryJewelrySets;

  /// No description provided for @subSubcategoryBodyJewelry.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Mücevherleri'**
  String get subSubcategoryBodyJewelry;

  /// No description provided for @subSubcategoryAnalogWatches.
  ///
  /// In tr, this message translates to:
  /// **'Analog Saatler'**
  String get subSubcategoryAnalogWatches;

  /// No description provided for @subSubcategoryDigitalWatches.
  ///
  /// In tr, this message translates to:
  /// **'Dijital Saatler'**
  String get subSubcategoryDigitalWatches;

  /// No description provided for @subSubcategorySmartwatches.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Saatler'**
  String get subSubcategorySmartwatches;

  /// No description provided for @subSubcategorySportsWatches.
  ///
  /// In tr, this message translates to:
  /// **'Spor Saatleri'**
  String get subSubcategorySportsWatches;

  /// No description provided for @subSubcategoryLuxuryWatches.
  ///
  /// In tr, this message translates to:
  /// **'Lüks Saatler'**
  String get subSubcategoryLuxuryWatches;

  /// No description provided for @subSubcategoryFashionWatches.
  ///
  /// In tr, this message translates to:
  /// **'Moda Saatleri'**
  String get subSubcategoryFashionWatches;

  /// No description provided for @subSubcategoryKidsWatches.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Saatleri'**
  String get subSubcategoryKidsWatches;

  /// No description provided for @subSubcategoryLeatherBelts.
  ///
  /// In tr, this message translates to:
  /// **'Deri Kemerler'**
  String get subSubcategoryLeatherBelts;

  /// No description provided for @subSubcategoryFabricBelts.
  ///
  /// In tr, this message translates to:
  /// **'Kumaş Kemerler'**
  String get subSubcategoryFabricBelts;

  /// No description provided for @subSubcategoryChainBelts.
  ///
  /// In tr, this message translates to:
  /// **'Zincir Kemerler'**
  String get subSubcategoryChainBelts;

  /// No description provided for @subSubcategoryDressBelts.
  ///
  /// In tr, this message translates to:
  /// **'Resmi Kemerler'**
  String get subSubcategoryDressBelts;

  /// No description provided for @subSubcategoryCasualBelts.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Kemerler'**
  String get subSubcategoryCasualBelts;

  /// No description provided for @subSubcategoryDesignerBelts.
  ///
  /// In tr, this message translates to:
  /// **'Tasarımcı Kemerler'**
  String get subSubcategoryDesignerBelts;

  /// No description provided for @subSubcategoryBaseballCaps.
  ///
  /// In tr, this message translates to:
  /// **'Beyzbol Şapkaları'**
  String get subSubcategoryBaseballCaps;

  /// No description provided for @subSubcategoryBeanies.
  ///
  /// In tr, this message translates to:
  /// **'Bereler'**
  String get subSubcategoryBeanies;

  /// No description provided for @subSubcategoryFedoras.
  ///
  /// In tr, this message translates to:
  /// **'Fötr Şapkalar'**
  String get subSubcategoryFedoras;

  /// No description provided for @subSubcategorySunHats.
  ///
  /// In tr, this message translates to:
  /// **'Güneş Şapkaları'**
  String get subSubcategorySunHats;

  /// No description provided for @subSubcategoryBucketHats.
  ///
  /// In tr, this message translates to:
  /// **'Bucket Şapkalar'**
  String get subSubcategoryBucketHats;

  /// No description provided for @subSubcategoryBerets.
  ///
  /// In tr, this message translates to:
  /// **'Fransız Bereleri'**
  String get subSubcategoryBerets;

  /// No description provided for @subSubcategorySnapbacks.
  ///
  /// In tr, this message translates to:
  /// **'Snapback Şapkalar'**
  String get subSubcategorySnapbacks;

  /// No description provided for @subSubcategorySilkScarves.
  ///
  /// In tr, this message translates to:
  /// **'İpek Atkılar'**
  String get subSubcategorySilkScarves;

  /// No description provided for @subSubcategoryWinterScarves.
  ///
  /// In tr, this message translates to:
  /// **'Kış Atkıları'**
  String get subSubcategoryWinterScarves;

  /// No description provided for @subSubcategoryShawls.
  ///
  /// In tr, this message translates to:
  /// **'Şallar'**
  String get subSubcategoryShawls;

  /// No description provided for @subSubcategoryPashminas.
  ///
  /// In tr, this message translates to:
  /// **'Paşminalar'**
  String get subSubcategoryPashminas;

  /// No description provided for @subSubcategoryBandanas.
  ///
  /// In tr, this message translates to:
  /// **'Bandanalar'**
  String get subSubcategoryBandanas;

  /// No description provided for @subSubcategoryWraps.
  ///
  /// In tr, this message translates to:
  /// **'Örtüler'**
  String get subSubcategoryWraps;

  /// No description provided for @subSubcategorySunglasses.
  ///
  /// In tr, this message translates to:
  /// **'Güneş Gözlükleri'**
  String get subSubcategorySunglasses;

  /// No description provided for @subSubcategoryReadingGlasses.
  ///
  /// In tr, this message translates to:
  /// **'Okuma Gözlükleri'**
  String get subSubcategoryReadingGlasses;

  /// No description provided for @subSubcategoryBlueLightGlasses.
  ///
  /// In tr, this message translates to:
  /// **'Mavi Işık Gözlükleri'**
  String get subSubcategoryBlueLightGlasses;

  /// No description provided for @subSubcategorySafetyGlasses.
  ///
  /// In tr, this message translates to:
  /// **'Koruyucu Gözlükler'**
  String get subSubcategorySafetyGlasses;

  /// No description provided for @subSubcategoryFashionGlasses.
  ///
  /// In tr, this message translates to:
  /// **'Moda Gözlükleri'**
  String get subSubcategoryFashionGlasses;

  /// No description provided for @subSubcategoryWinterGloves.
  ///
  /// In tr, this message translates to:
  /// **'Kış Eldivenleri'**
  String get subSubcategoryWinterGloves;

  /// No description provided for @subSubcategoryDressGloves.
  ///
  /// In tr, this message translates to:
  /// **'Resmi Eldivenler'**
  String get subSubcategoryDressGloves;

  /// No description provided for @subSubcategoryWorkGloves.
  ///
  /// In tr, this message translates to:
  /// **'İş Eldivenleri'**
  String get subSubcategoryWorkGloves;

  /// No description provided for @subSubcategorySportsGloves.
  ///
  /// In tr, this message translates to:
  /// **'Spor Eldivenleri'**
  String get subSubcategorySportsGloves;

  /// No description provided for @subSubcategoryTouchscreenGloves.
  ///
  /// In tr, this message translates to:
  /// **'Dokunmatik Eldivenler'**
  String get subSubcategoryTouchscreenGloves;

  /// No description provided for @subSubcategoryHairClips.
  ///
  /// In tr, this message translates to:
  /// **'Saç Tokaları'**
  String get subSubcategoryHairClips;

  /// No description provided for @subSubcategoryHeadbands.
  ///
  /// In tr, this message translates to:
  /// **'Saç Bantları'**
  String get subSubcategoryHeadbands;

  /// No description provided for @subSubcategoryHairTies.
  ///
  /// In tr, this message translates to:
  /// **'Saç Lastiği'**
  String get subSubcategoryHairTies;

  /// No description provided for @subSubcategoryBobbyPins.
  ///
  /// In tr, this message translates to:
  /// **'Saç Tokası'**
  String get subSubcategoryBobbyPins;

  /// No description provided for @subSubcategoryHairScarves.
  ///
  /// In tr, this message translates to:
  /// **'Saç Atkıları'**
  String get subSubcategoryHairScarves;

  /// No description provided for @subSubcategoryHairJewelry.
  ///
  /// In tr, this message translates to:
  /// **'Saç Mücevherleri'**
  String get subSubcategoryHairJewelry;

  /// No description provided for @subSubcategoryKeychains.
  ///
  /// In tr, this message translates to:
  /// **'Anahtarlıklar'**
  String get subSubcategoryKeychains;

  /// No description provided for @subSubcategoryPhoneCases.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Kılıfları'**
  String get subSubcategoryPhoneCases;

  /// No description provided for @subSubcategoryWallets.
  ///
  /// In tr, this message translates to:
  /// **'Cüzdanlar'**
  String get subSubcategoryWallets;

  /// No description provided for @subSubcategoryPurseAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Çanta Aksesuarları'**
  String get subSubcategoryPurseAccessories;

  /// No description provided for @subSubcategoryPinsBadges.
  ///
  /// In tr, this message translates to:
  /// **'Rozetler ve Rozet'**
  String get subSubcategoryPinsBadges;

  /// No description provided for @subSubcategoryBodysuits.
  ///
  /// In tr, this message translates to:
  /// **'Body'**
  String get subSubcategoryBodysuits;

  /// No description provided for @subSubcategoryRompers.
  ///
  /// In tr, this message translates to:
  /// **'Tulum'**
  String get subSubcategoryRompers;

  /// No description provided for @subSubcategoryBabySets.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Takımları'**
  String get subSubcategoryBabySets;

  /// No description provided for @subSubcategoryBabySleepwear.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Pijamaları'**
  String get subSubcategoryBabySleepwear;

  /// No description provided for @subSubcategoryBabySocks.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Çorapları'**
  String get subSubcategoryBabySocks;

  /// No description provided for @subSubcategoryBabyHats.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Şapkaları'**
  String get subSubcategoryBabyHats;

  /// No description provided for @subSubcategoryBabyMittens.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Eldivenleri'**
  String get subSubcategoryBabyMittens;

  /// No description provided for @subSubcategoryKidsTShirts.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Tişörtleri'**
  String get subSubcategoryKidsTShirts;

  /// No description provided for @subSubcategoryKidsPants.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Pantolonları'**
  String get subSubcategoryKidsPants;

  /// No description provided for @subSubcategoryKidsDresses.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Elbiseleri'**
  String get subSubcategoryKidsDresses;

  /// No description provided for @subSubcategoryKidsSweatshirts.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Sweatshirtleri'**
  String get subSubcategoryKidsSweatshirts;

  /// No description provided for @subSubcategoryKidsJackets.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Ceketleri'**
  String get subSubcategoryKidsJackets;

  /// No description provided for @subSubcategoryKidsPajamas.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Pijamaları'**
  String get subSubcategoryKidsPajamas;

  /// No description provided for @subSubcategorySchoolUniforms.
  ///
  /// In tr, this message translates to:
  /// **'Okul Üniformaları'**
  String get subSubcategorySchoolUniforms;

  /// No description provided for @subSubcategoryKidsSneakers.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Spor Ayakkabı'**
  String get subSubcategoryKidsSneakers;

  /// No description provided for @subSubcategoryKidsSandals.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Sandaletleri'**
  String get subSubcategoryKidsSandals;

  /// No description provided for @subSubcategoryKidsBoots.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Botları'**
  String get subSubcategoryKidsBoots;

  /// No description provided for @subSubcategorySchoolShoes.
  ///
  /// In tr, this message translates to:
  /// **'Okul Ayakkabıları'**
  String get subSubcategorySchoolShoes;

  /// No description provided for @subSubcategorySportsShoes.
  ///
  /// In tr, this message translates to:
  /// **'Spor Ayakkabıları'**
  String get subSubcategorySportsShoes;

  /// No description provided for @subSubcategoryKidsRainBoots.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Yağmur Çizmeleri'**
  String get subSubcategoryKidsRainBoots;

  /// No description provided for @subSubcategoryKidsSlippers.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Terlikleri'**
  String get subSubcategoryKidsSlippers;

  /// No description provided for @subSubcategoryEducationalToys.
  ///
  /// In tr, this message translates to:
  /// **'Eğitici Oyuncaklar'**
  String get subSubcategoryEducationalToys;

  /// No description provided for @subSubcategoryPlushToys.
  ///
  /// In tr, this message translates to:
  /// **'Peluş Oyuncaklar'**
  String get subSubcategoryPlushToys;

  /// No description provided for @subSubcategoryBuildingBlocks.
  ///
  /// In tr, this message translates to:
  /// **'Yapı Blokları'**
  String get subSubcategoryBuildingBlocks;

  /// No description provided for @subSubcategoryDollsActionFigures.
  ///
  /// In tr, this message translates to:
  /// **'Bebekler ve Aksiyon Figürleri'**
  String get subSubcategoryDollsActionFigures;

  /// No description provided for @subSubcategoryPuzzles.
  ///
  /// In tr, this message translates to:
  /// **'Yapbozlar'**
  String get subSubcategoryPuzzles;

  /// No description provided for @subSubcategoryBoardGames.
  ///
  /// In tr, this message translates to:
  /// **'Masa Oyunları'**
  String get subSubcategoryBoardGames;

  /// No description provided for @subSubcategoryElectronicToys.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik Oyuncaklar'**
  String get subSubcategoryElectronicToys;

  /// No description provided for @subSubcategoryOutdoorPlay.
  ///
  /// In tr, this message translates to:
  /// **'Outdoor Oyuncak'**
  String get subSubcategoryOutdoorPlay;

  /// No description provided for @subSubcategoryDiapers.
  ///
  /// In tr, this message translates to:
  /// **'Bezler'**
  String get subSubcategoryDiapers;

  /// No description provided for @subSubcategoryBabyWipes.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Mendilleri'**
  String get subSubcategoryBabyWipes;

  /// No description provided for @subSubcategoryBabySkincare.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Cilt Bakımı'**
  String get subSubcategoryBabySkincare;

  /// No description provided for @subSubcategoryBabyBathProducts.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Banyo Ürünleri'**
  String get subSubcategoryBabyBathProducts;

  /// No description provided for @subSubcategoryBabyHealth.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Sağlığı'**
  String get subSubcategoryBabyHealth;

  /// No description provided for @subSubcategoryBabyMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Monitörleri'**
  String get subSubcategoryBabyMonitors;

  /// No description provided for @subSubcategoryMaternityClothing.
  ///
  /// In tr, this message translates to:
  /// **'Hamile Giyim'**
  String get subSubcategoryMaternityClothing;

  /// No description provided for @subSubcategoryNursingBras.
  ///
  /// In tr, this message translates to:
  /// **'Emzirme Sütyenleri'**
  String get subSubcategoryNursingBras;

  /// No description provided for @subSubcategoryMaternityAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Hamilelik Aksesuarları'**
  String get subSubcategoryMaternityAccessories;

  /// No description provided for @subSubcategoryPregnancySupport.
  ///
  /// In tr, this message translates to:
  /// **'Hamilelik Desteği'**
  String get subSubcategoryPregnancySupport;

  /// No description provided for @subSubcategoryStrollers.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Arabaları'**
  String get subSubcategoryStrollers;

  /// No description provided for @subSubcategoryCarSeats.
  ///
  /// In tr, this message translates to:
  /// **'Oto Koltukları'**
  String get subSubcategoryCarSeats;

  /// No description provided for @subSubcategoryTravelSystems.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Sistemleri'**
  String get subSubcategoryTravelSystems;

  /// No description provided for @subSubcategoryBoosterSeats.
  ///
  /// In tr, this message translates to:
  /// **'Yükseltici Koltuklar'**
  String get subSubcategoryBoosterSeats;

  /// No description provided for @subSubcategoryStrollerAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Arabası Aksesuarları'**
  String get subSubcategoryStrollerAccessories;

  /// No description provided for @subSubcategoryBabyBottles.
  ///
  /// In tr, this message translates to:
  /// **'Biberon'**
  String get subSubcategoryBabyBottles;

  /// No description provided for @subSubcategoryBreastPumps.
  ///
  /// In tr, this message translates to:
  /// **'Göğüs Pompaları'**
  String get subSubcategoryBreastPumps;

  /// No description provided for @subSubcategoryPacifiers.
  ///
  /// In tr, this message translates to:
  /// **'Emzikler'**
  String get subSubcategoryPacifiers;

  /// No description provided for @subSubcategoryHighChairs.
  ///
  /// In tr, this message translates to:
  /// **'Mama Sandalyeleri'**
  String get subSubcategoryHighChairs;

  /// No description provided for @subSubcategoryFeedingAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Beslenme Aksesuarları'**
  String get subSubcategoryFeedingAccessories;

  /// No description provided for @subSubcategoryBabyFood.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Maması'**
  String get subSubcategoryBabyFood;

  /// No description provided for @subSubcategoryBabyGates.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Bariyerleri'**
  String get subSubcategoryBabyGates;

  /// No description provided for @subSubcategoryOutletCovers.
  ///
  /// In tr, this message translates to:
  /// **'Priz Koruyucuları'**
  String get subSubcategoryOutletCovers;

  /// No description provided for @subSubcategoryCabinetLocks.
  ///
  /// In tr, this message translates to:
  /// **'Dolap Kilitleri'**
  String get subSubcategoryCabinetLocks;

  /// No description provided for @subSubcategoryCornerGuards.
  ///
  /// In tr, this message translates to:
  /// **'Köşe Koruyucuları'**
  String get subSubcategoryCornerGuards;

  /// No description provided for @subSubcategorySafetyBabyMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Bebek Monitörleri'**
  String get subSubcategorySafetyBabyMonitors;

  /// No description provided for @subSubcategoryLearningToys.
  ///
  /// In tr, this message translates to:
  /// **'Öğrenme Oyuncakları'**
  String get subSubcategoryLearningToys;

  /// No description provided for @subSubcategoryEducationalBooks.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Kitapları'**
  String get subSubcategoryEducationalBooks;

  /// No description provided for @subSubcategoryFlashCards.
  ///
  /// In tr, this message translates to:
  /// **'Flash Kartlar'**
  String get subSubcategoryFlashCards;

  /// No description provided for @subSubcategoryScienceKits.
  ///
  /// In tr, this message translates to:
  /// **'Bilim Setleri'**
  String get subSubcategoryScienceKits;

  /// No description provided for @subSubcategoryEducationalMusicalInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Eğitici Müzik Aletleri'**
  String get subSubcategoryEducationalMusicalInstruments;

  /// No description provided for @subSubcategorySofas.
  ///
  /// In tr, this message translates to:
  /// **'Koltuk Takımları'**
  String get subSubcategorySofas;

  /// No description provided for @subSubcategoryArmchairs.
  ///
  /// In tr, this message translates to:
  /// **'Berjerler'**
  String get subSubcategoryArmchairs;

  /// No description provided for @subSubcategoryCoffeeTables.
  ///
  /// In tr, this message translates to:
  /// **'Sehpalar'**
  String get subSubcategoryCoffeeTables;

  /// No description provided for @subSubcategoryTVStands.
  ///
  /// In tr, this message translates to:
  /// **'TV Üniteleri'**
  String get subSubcategoryTVStands;

  /// No description provided for @subSubcategoryBookcases.
  ///
  /// In tr, this message translates to:
  /// **'Kitaplıklar'**
  String get subSubcategoryBookcases;

  /// No description provided for @subSubcategorySideTables.
  ///
  /// In tr, this message translates to:
  /// **'Yan Sehpalar'**
  String get subSubcategorySideTables;

  /// No description provided for @subSubcategoryOttoman.
  ///
  /// In tr, this message translates to:
  /// **'Puflar'**
  String get subSubcategoryOttoman;

  /// No description provided for @subSubcategoryRecliners.
  ///
  /// In tr, this message translates to:
  /// **'Dinlenme Koltukları'**
  String get subSubcategoryRecliners;

  /// No description provided for @subSubcategoryBeds.
  ///
  /// In tr, this message translates to:
  /// **'Yatak'**
  String get subSubcategoryBeds;

  /// No description provided for @subSubcategoryMattresses.
  ///
  /// In tr, this message translates to:
  /// **'Yatak'**
  String get subSubcategoryMattresses;

  /// No description provided for @subSubcategoryWardrobes.
  ///
  /// In tr, this message translates to:
  /// **'Dolaplar'**
  String get subSubcategoryWardrobes;

  /// No description provided for @subSubcategoryDressers.
  ///
  /// In tr, this message translates to:
  /// **'Şifonyerler'**
  String get subSubcategoryDressers;

  /// No description provided for @subSubcategoryNightstands.
  ///
  /// In tr, this message translates to:
  /// **'Komodinler'**
  String get subSubcategoryNightstands;

  /// No description provided for @subSubcategoryMirrors.
  ///
  /// In tr, this message translates to:
  /// **'Aynalar'**
  String get subSubcategoryMirrors;

  /// No description provided for @subSubcategoryBedFrames.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Çerçeveleri'**
  String get subSubcategoryBedFrames;

  /// No description provided for @subSubcategoryHeadboards.
  ///
  /// In tr, this message translates to:
  /// **'Başlıklar'**
  String get subSubcategoryHeadboards;

  /// No description provided for @subSubcategoryDiningTables.
  ///
  /// In tr, this message translates to:
  /// **'Yemek Masaları'**
  String get subSubcategoryDiningTables;

  /// No description provided for @subSubcategoryDiningChairs.
  ///
  /// In tr, this message translates to:
  /// **'Yemek Sandalyeleri'**
  String get subSubcategoryDiningChairs;

  /// No description provided for @subSubcategoryBarStools.
  ///
  /// In tr, this message translates to:
  /// **'Bar Tabureleri'**
  String get subSubcategoryBarStools;

  /// No description provided for @subSubcategoryKitchenIslands.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Adaları'**
  String get subSubcategoryKitchenIslands;

  /// No description provided for @subSubcategoryCookware.
  ///
  /// In tr, this message translates to:
  /// **'Pişirme Araçları'**
  String get subSubcategoryCookware;

  /// No description provided for @subSubcategoryDinnerware.
  ///
  /// In tr, this message translates to:
  /// **'Yemek Takımları'**
  String get subSubcategoryDinnerware;

  /// No description provided for @subSubcategoryGlassware.
  ///
  /// In tr, this message translates to:
  /// **'Cam Eşyalar'**
  String get subSubcategoryGlassware;

  /// No description provided for @subSubcategoryKitchenAppliances.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Aletleri'**
  String get subSubcategoryKitchenAppliances;

  /// No description provided for @subSubcategoryUtensils.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Gereçleri'**
  String get subSubcategoryUtensils;

  /// No description provided for @subSubcategoryBathroomVanities.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Dolabı'**
  String get subSubcategoryBathroomVanities;

  /// No description provided for @subSubcategoryShowerCurtains.
  ///
  /// In tr, this message translates to:
  /// **'Duş Perdeleri'**
  String get subSubcategoryShowerCurtains;

  /// No description provided for @subSubcategoryBathMats.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Paspasları'**
  String get subSubcategoryBathMats;

  /// No description provided for @subSubcategoryTowelRacks.
  ///
  /// In tr, this message translates to:
  /// **'Havlu Askıları'**
  String get subSubcategoryTowelRacks;

  /// No description provided for @subSubcategoryBathroomStorage.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Saklama'**
  String get subSubcategoryBathroomStorage;

  /// No description provided for @subSubcategoryBathroomMirrors.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Aynaları'**
  String get subSubcategoryBathroomMirrors;

  /// No description provided for @subSubcategoryBathroomAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Aksesuarları'**
  String get subSubcategoryBathroomAccessories;

  /// No description provided for @subSubcategoryWallArt.
  ///
  /// In tr, this message translates to:
  /// **'Duvar Sanatı'**
  String get subSubcategoryWallArt;

  /// No description provided for @subSubcategoryDecorativeObjects.
  ///
  /// In tr, this message translates to:
  /// **'Dekoratif Objeler'**
  String get subSubcategoryDecorativeObjects;

  /// No description provided for @subSubcategoryCandles.
  ///
  /// In tr, this message translates to:
  /// **'Mumlar'**
  String get subSubcategoryCandles;

  /// No description provided for @subSubcategoryVases.
  ///
  /// In tr, this message translates to:
  /// **'Vazolar'**
  String get subSubcategoryVases;

  /// No description provided for @subSubcategoryPictureFrames.
  ///
  /// In tr, this message translates to:
  /// **'Resim Çerçeveleri'**
  String get subSubcategoryPictureFrames;

  /// No description provided for @subSubcategoryClocks.
  ///
  /// In tr, this message translates to:
  /// **'Saatler'**
  String get subSubcategoryClocks;

  /// No description provided for @subSubcategoryArtificialPlants.
  ///
  /// In tr, this message translates to:
  /// **'Yapay Bitkiler'**
  String get subSubcategoryArtificialPlants;

  /// No description provided for @subSubcategorySculptures.
  ///
  /// In tr, this message translates to:
  /// **'Heykeller'**
  String get subSubcategorySculptures;

  /// No description provided for @subSubcategoryCeilingLights.
  ///
  /// In tr, this message translates to:
  /// **'Avize'**
  String get subSubcategoryCeilingLights;

  /// No description provided for @subSubcategoryTableLamps.
  ///
  /// In tr, this message translates to:
  /// **'Masa Lambaları'**
  String get subSubcategoryTableLamps;

  /// No description provided for @subSubcategoryFloorLamps.
  ///
  /// In tr, this message translates to:
  /// **'Yer Lambaları'**
  String get subSubcategoryFloorLamps;

  /// No description provided for @subSubcategoryWallLights.
  ///
  /// In tr, this message translates to:
  /// **'Duvar Aplikleri'**
  String get subSubcategoryWallLights;

  /// No description provided for @subSubcategoryPendantLights.
  ///
  /// In tr, this message translates to:
  /// **'Sarkıt Aydınlatma'**
  String get subSubcategoryPendantLights;

  /// No description provided for @subSubcategoryChandelier.
  ///
  /// In tr, this message translates to:
  /// **'Kristal Avizeler'**
  String get subSubcategoryChandelier;

  /// No description provided for @subSubcategoryStringLights.
  ///
  /// In tr, this message translates to:
  /// **'Dekoratif Işıklar'**
  String get subSubcategoryStringLights;

  /// No description provided for @subSubcategoryNightLights.
  ///
  /// In tr, this message translates to:
  /// **'Gece Lambaları'**
  String get subSubcategoryNightLights;

  /// No description provided for @subSubcategoryShelvingUnits.
  ///
  /// In tr, this message translates to:
  /// **'Raf Sistemleri'**
  String get subSubcategoryShelvingUnits;

  /// No description provided for @subSubcategoryStorageBoxes.
  ///
  /// In tr, this message translates to:
  /// **'Saklama Kutuları'**
  String get subSubcategoryStorageBoxes;

  /// No description provided for @subSubcategoryBaskets.
  ///
  /// In tr, this message translates to:
  /// **'Sepetler'**
  String get subSubcategoryBaskets;

  /// No description provided for @subSubcategoryHangers.
  ///
  /// In tr, this message translates to:
  /// **'Askılar'**
  String get subSubcategoryHangers;

  /// No description provided for @subSubcategoryClosetOrganizers.
  ///
  /// In tr, this message translates to:
  /// **'Dolap Organizerleri'**
  String get subSubcategoryClosetOrganizers;

  /// No description provided for @subSubcategoryDrawerOrganizers.
  ///
  /// In tr, this message translates to:
  /// **'Çekmece Organizerleri'**
  String get subSubcategoryDrawerOrganizers;

  /// No description provided for @subSubcategoryStorageBins.
  ///
  /// In tr, this message translates to:
  /// **'Saklama Kasaları'**
  String get subSubcategoryStorageBins;

  /// No description provided for @subSubcategoryCurtains.
  ///
  /// In tr, this message translates to:
  /// **'Perdeler'**
  String get subSubcategoryCurtains;

  /// No description provided for @subSubcategoryBlinds.
  ///
  /// In tr, this message translates to:
  /// **'Jaluziler'**
  String get subSubcategoryBlinds;

  /// No description provided for @subSubcategoryRugs.
  ///
  /// In tr, this message translates to:
  /// **'Halılar'**
  String get subSubcategoryRugs;

  /// No description provided for @subSubcategoryCushions.
  ///
  /// In tr, this message translates to:
  /// **'Yastıklar'**
  String get subSubcategoryCushions;

  /// No description provided for @subSubcategoryThrows.
  ///
  /// In tr, this message translates to:
  /// **'Battaniyeler'**
  String get subSubcategoryThrows;

  /// No description provided for @subSubcategoryBedLinens.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Çarşafları'**
  String get subSubcategoryBedLinens;

  /// No description provided for @subSubcategoryTowels.
  ///
  /// In tr, this message translates to:
  /// **'Havlular'**
  String get subSubcategoryTowels;

  /// No description provided for @subSubcategoryBlankets.
  ///
  /// In tr, this message translates to:
  /// **'Örtüler'**
  String get subSubcategoryBlankets;

  /// No description provided for @subSubcategoryGardenFurniture.
  ///
  /// In tr, this message translates to:
  /// **'Bahçe Mobilyaları'**
  String get subSubcategoryGardenFurniture;

  /// No description provided for @subSubcategoryPlantPots.
  ///
  /// In tr, this message translates to:
  /// **'Saksılar'**
  String get subSubcategoryPlantPots;

  /// No description provided for @subSubcategoryGardenTools.
  ///
  /// In tr, this message translates to:
  /// **'Bahçe Aletleri'**
  String get subSubcategoryGardenTools;

  /// No description provided for @subSubcategoryOutdoorLighting.
  ///
  /// In tr, this message translates to:
  /// **'Dış Mekan Aydınlatma'**
  String get subSubcategoryOutdoorLighting;

  /// No description provided for @subSubcategoryBBQGrills.
  ///
  /// In tr, this message translates to:
  /// **'Barbekü ve Izgara'**
  String get subSubcategoryBBQGrills;

  /// No description provided for @subSubcategoryUmbrellas.
  ///
  /// In tr, this message translates to:
  /// **'Şemsiyeler'**
  String get subSubcategoryUmbrellas;

  /// No description provided for @subSubcategoryGardenDecor.
  ///
  /// In tr, this message translates to:
  /// **'Bahçe Dekorasyonu'**
  String get subSubcategoryGardenDecor;

  /// No description provided for @subSubcategoryCleaners.
  ///
  /// In tr, this message translates to:
  /// **'Temizleyiciler'**
  String get subSubcategoryCleaners;

  /// No description provided for @subSubcategoryMoisturizers.
  ///
  /// In tr, this message translates to:
  /// **'Nemlendiriciler'**
  String get subSubcategoryMoisturizers;

  /// No description provided for @subSubcategorySerums.
  ///
  /// In tr, this message translates to:
  /// **'Serumlar'**
  String get subSubcategorySerums;

  /// No description provided for @subSubcategoryFaceMasks.
  ///
  /// In tr, this message translates to:
  /// **'Yüz Maskeleri'**
  String get subSubcategoryFaceMasks;

  /// No description provided for @subSubcategorySunscreen.
  ///
  /// In tr, this message translates to:
  /// **'Güneş Kremi'**
  String get subSubcategorySunscreen;

  /// No description provided for @subSubcategoryToners.
  ///
  /// In tr, this message translates to:
  /// **'Tonikler'**
  String get subSubcategoryToners;

  /// No description provided for @subSubcategoryEyeCreams.
  ///
  /// In tr, this message translates to:
  /// **'Göz Kremleri'**
  String get subSubcategoryEyeCreams;

  /// No description provided for @subSubcategoryAntiAging.
  ///
  /// In tr, this message translates to:
  /// **'Yaşlanma Karşıtı'**
  String get subSubcategoryAntiAging;

  /// No description provided for @subSubcategoryAcneTreatment.
  ///
  /// In tr, this message translates to:
  /// **'Akne Tedavisi'**
  String get subSubcategoryAcneTreatment;

  /// No description provided for @subSubcategoryFoundation.
  ///
  /// In tr, this message translates to:
  /// **'Fondöten'**
  String get subSubcategoryFoundation;

  /// No description provided for @subSubcategoryConcealer.
  ///
  /// In tr, this message translates to:
  /// **'Kapatıcı'**
  String get subSubcategoryConcealer;

  /// No description provided for @subSubcategoryPowder.
  ///
  /// In tr, this message translates to:
  /// **'Pudra'**
  String get subSubcategoryPowder;

  /// No description provided for @subSubcategoryBlush.
  ///
  /// In tr, this message translates to:
  /// **'Allık'**
  String get subSubcategoryBlush;

  /// No description provided for @subSubcategoryBronzer.
  ///
  /// In tr, this message translates to:
  /// **'Bronzlaştırıcı'**
  String get subSubcategoryBronzer;

  /// No description provided for @subSubcategoryHighlighter.
  ///
  /// In tr, this message translates to:
  /// **'Aydınlatıcı'**
  String get subSubcategoryHighlighter;

  /// No description provided for @subSubcategoryEyeshadow.
  ///
  /// In tr, this message translates to:
  /// **'Göz Farı'**
  String get subSubcategoryEyeshadow;

  /// No description provided for @subSubcategoryEyeliner.
  ///
  /// In tr, this message translates to:
  /// **'Göz Kalemi'**
  String get subSubcategoryEyeliner;

  /// No description provided for @subSubcategoryMascara.
  ///
  /// In tr, this message translates to:
  /// **'Maskara'**
  String get subSubcategoryMascara;

  /// No description provided for @subSubcategoryLipstick.
  ///
  /// In tr, this message translates to:
  /// **'Ruj'**
  String get subSubcategoryLipstick;

  /// No description provided for @subSubcategoryLipGloss.
  ///
  /// In tr, this message translates to:
  /// **'Dudak Parlatıcısı'**
  String get subSubcategoryLipGloss;

  /// No description provided for @subSubcategoryMakeupBrushes.
  ///
  /// In tr, this message translates to:
  /// **'Makyaj Fırçaları'**
  String get subSubcategoryMakeupBrushes;

  /// No description provided for @subSubcategoryShampoo.
  ///
  /// In tr, this message translates to:
  /// **'Şampuan'**
  String get subSubcategoryShampoo;

  /// No description provided for @subSubcategoryConditioner.
  ///
  /// In tr, this message translates to:
  /// **'Saç Kremi'**
  String get subSubcategoryConditioner;

  /// No description provided for @subSubcategoryHairMasks.
  ///
  /// In tr, this message translates to:
  /// **'Saç Maskeleri'**
  String get subSubcategoryHairMasks;

  /// No description provided for @subSubcategoryHairOils.
  ///
  /// In tr, this message translates to:
  /// **'Saç Yağları'**
  String get subSubcategoryHairOils;

  /// No description provided for @subSubcategoryStylingProducts.
  ///
  /// In tr, this message translates to:
  /// **'Şekillendirici Ürünler'**
  String get subSubcategoryStylingProducts;

  /// No description provided for @subSubcategoryHairColor.
  ///
  /// In tr, this message translates to:
  /// **'Saç Boyası'**
  String get subSubcategoryHairColor;

  /// No description provided for @subSubcategoryHairTools.
  ///
  /// In tr, this message translates to:
  /// **'Saç Araçları'**
  String get subSubcategoryHairTools;

  /// No description provided for @subSubcategoryPerfumes.
  ///
  /// In tr, this message translates to:
  /// **'Parfümler'**
  String get subSubcategoryPerfumes;

  /// No description provided for @subSubcategoryEauDeToilette.
  ///
  /// In tr, this message translates to:
  /// **'Eau de Toilette'**
  String get subSubcategoryEauDeToilette;

  /// No description provided for @subSubcategoryBodySprays.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Spreyleri'**
  String get subSubcategoryBodySprays;

  /// No description provided for @subSubcategoryDeodorants.
  ///
  /// In tr, this message translates to:
  /// **'Deodorantlar'**
  String get subSubcategoryDeodorants;

  /// No description provided for @subSubcategoryColognes.
  ///
  /// In tr, this message translates to:
  /// **'Kolonya'**
  String get subSubcategoryColognes;

  /// No description provided for @subSubcategoryEssentialOils.
  ///
  /// In tr, this message translates to:
  /// **'Esansiyel Yağlar'**
  String get subSubcategoryEssentialOils;

  /// No description provided for @subSubcategoryBodyWash.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Şampuanı'**
  String get subSubcategoryBodyWash;

  /// No description provided for @subSubcategorySoap.
  ///
  /// In tr, this message translates to:
  /// **'Sabun'**
  String get subSubcategorySoap;

  /// No description provided for @subSubcategoryPersonalHygieneShampoo.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Hijyen Şampuanı'**
  String get subSubcategoryPersonalHygieneShampoo;

  /// No description provided for @subSubcategoryPersonalHygieneDeodorants.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Hijyen Deodorantları'**
  String get subSubcategoryPersonalHygieneDeodorants;

  /// No description provided for @subSubcategoryFeminineCare.
  ///
  /// In tr, this message translates to:
  /// **'Kadın Hijyeni'**
  String get subSubcategoryFeminineCare;

  /// No description provided for @subSubcategoryMensGrooming.
  ///
  /// In tr, this message translates to:
  /// **'Erkek Bakımı'**
  String get subSubcategoryMensGrooming;

  /// No description provided for @subSubcategoryIntimateCare.
  ///
  /// In tr, this message translates to:
  /// **'İntim Bakım'**
  String get subSubcategoryIntimateCare;

  /// No description provided for @subSubcategoryNailPolish.
  ///
  /// In tr, this message translates to:
  /// **'Oje'**
  String get subSubcategoryNailPolish;

  /// No description provided for @subSubcategoryNailTools.
  ///
  /// In tr, this message translates to:
  /// **'Tırnak Araçları'**
  String get subSubcategoryNailTools;

  /// No description provided for @subSubcategoryNailTreatments.
  ///
  /// In tr, this message translates to:
  /// **'Tırnak Bakımı'**
  String get subSubcategoryNailTreatments;

  /// No description provided for @subSubcategoryNailArt.
  ///
  /// In tr, this message translates to:
  /// **'Nail Art'**
  String get subSubcategoryNailArt;

  /// No description provided for @subSubcategoryCuticleCare.
  ///
  /// In tr, this message translates to:
  /// **'Kütikül Bakımı'**
  String get subSubcategoryCuticleCare;

  /// No description provided for @subSubcategoryNailFiles.
  ///
  /// In tr, this message translates to:
  /// **'Tırnak Törpüleri'**
  String get subSubcategoryNailFiles;

  /// No description provided for @subSubcategoryBodyLotions.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Losyonları'**
  String get subSubcategoryBodyLotions;

  /// No description provided for @subSubcategoryBodyOils.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Yağları'**
  String get subSubcategoryBodyOils;

  /// No description provided for @subSubcategoryBodyScrubs.
  ///
  /// In tr, this message translates to:
  /// **'Vücut Peelingleri'**
  String get subSubcategoryBodyScrubs;

  /// No description provided for @subSubcategoryHandCream.
  ///
  /// In tr, this message translates to:
  /// **'El Kremleri'**
  String get subSubcategoryHandCream;

  /// No description provided for @subSubcategoryFootCare.
  ///
  /// In tr, this message translates to:
  /// **'Ayak Bakımı'**
  String get subSubcategoryFootCare;

  /// No description provided for @subSubcategoryBathProducts.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Ürünleri'**
  String get subSubcategoryBathProducts;

  /// No description provided for @subSubcategoryMassageOils.
  ///
  /// In tr, this message translates to:
  /// **'Masaj Yağları'**
  String get subSubcategoryMassageOils;

  /// No description provided for @subSubcategoryToothbrushes.
  ///
  /// In tr, this message translates to:
  /// **'Diş Fırçaları'**
  String get subSubcategoryToothbrushes;

  /// No description provided for @subSubcategoryToothpaste.
  ///
  /// In tr, this message translates to:
  /// **'Diş Macunu'**
  String get subSubcategoryToothpaste;

  /// No description provided for @subSubcategoryMouthwash.
  ///
  /// In tr, this message translates to:
  /// **'Ağız Çalkalama Suyu'**
  String get subSubcategoryMouthwash;

  /// No description provided for @subSubcategoryDentalFloss.
  ///
  /// In tr, this message translates to:
  /// **'Diş İpi'**
  String get subSubcategoryDentalFloss;

  /// No description provided for @subSubcategoryTeethWhitening.
  ///
  /// In tr, this message translates to:
  /// **'Diş Beyazlatma'**
  String get subSubcategoryTeethWhitening;

  /// No description provided for @subSubcategoryOralHealth.
  ///
  /// In tr, this message translates to:
  /// **'Ağız Sağlığı'**
  String get subSubcategoryOralHealth;

  /// No description provided for @subSubcategoryBeautyMakeupBrushes.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Makyaj Fırçaları'**
  String get subSubcategoryBeautyMakeupBrushes;

  /// No description provided for @subSubcategoryBeautySponges.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Süngerleri'**
  String get subSubcategoryBeautySponges;

  /// No description provided for @subSubcategoryHairBrushes.
  ///
  /// In tr, this message translates to:
  /// **'Saç Fırçaları'**
  String get subSubcategoryHairBrushes;

  /// No description provided for @subSubcategoryBeautyMirrors.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Aynaları'**
  String get subSubcategoryBeautyMirrors;

  /// No description provided for @subSubcategoryTweezers.
  ///
  /// In tr, this message translates to:
  /// **'Cımbızlar'**
  String get subSubcategoryTweezers;

  /// No description provided for @subSubcategoryNailClippers.
  ///
  /// In tr, this message translates to:
  /// **'Tırnak Makasları'**
  String get subSubcategoryNailClippers;

  /// No description provided for @subSubcategoryBeautyCases.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Çantaları'**
  String get subSubcategoryBeautyCases;

  /// No description provided for @subSubcategoryToteBags.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş Çantaları'**
  String get subSubcategoryToteBags;

  /// No description provided for @subSubcategoryShoulderBags.
  ///
  /// In tr, this message translates to:
  /// **'Omuz Çantaları'**
  String get subSubcategoryShoulderBags;

  /// No description provided for @subSubcategoryCrossbodyBags.
  ///
  /// In tr, this message translates to:
  /// **'Çapraz Çantalar'**
  String get subSubcategoryCrossbodyBags;

  /// No description provided for @subSubcategoryClutches.
  ///
  /// In tr, this message translates to:
  /// **'Portföy Çantalar'**
  String get subSubcategoryClutches;

  /// No description provided for @subSubcategoryEveningBags.
  ///
  /// In tr, this message translates to:
  /// **'Gece Çantaları'**
  String get subSubcategoryEveningBags;

  /// No description provided for @subSubcategorySatchels.
  ///
  /// In tr, this message translates to:
  /// **'Askılı Çantalar'**
  String get subSubcategorySatchels;

  /// No description provided for @subSubcategoryHoboBags.
  ///
  /// In tr, this message translates to:
  /// **'Hobo Çantalar'**
  String get subSubcategoryHoboBags;

  /// No description provided for @subSubcategorySchoolBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Okul Sırt Çantaları'**
  String get subSubcategorySchoolBackpacks;

  /// No description provided for @subSubcategoryTravelBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Sırt Çantaları'**
  String get subSubcategoryTravelBackpacks;

  /// No description provided for @subSubcategoryLaptopBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Laptop Sırt Çantaları'**
  String get subSubcategoryLaptopBackpacks;

  /// No description provided for @subSubcategoryHikingBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Trekking Sırt Çantaları'**
  String get subSubcategoryHikingBackpacks;

  /// No description provided for @subSubcategoryCasualBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Sırt Çantaları'**
  String get subSubcategoryCasualBackpacks;

  /// No description provided for @subSubcategoryKidsBackpacks.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Sırt Çantaları'**
  String get subSubcategoryKidsBackpacks;

  /// No description provided for @subSubcategorySuitcases.
  ///
  /// In tr, this message translates to:
  /// **'Bavullar'**
  String get subSubcategorySuitcases;

  /// No description provided for @subSubcategoryCarryOnBags.
  ///
  /// In tr, this message translates to:
  /// **'Kabin Çantaları'**
  String get subSubcategoryCarryOnBags;

  /// No description provided for @subSubcategoryTravelDuffelBags.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Spor Çantaları'**
  String get subSubcategoryTravelDuffelBags;

  /// No description provided for @subSubcategoryLuggageSets.
  ///
  /// In tr, this message translates to:
  /// **'Bavul Setleri'**
  String get subSubcategoryLuggageSets;

  /// No description provided for @subSubcategoryGarmentBags.
  ///
  /// In tr, this message translates to:
  /// **'Takım Çantaları'**
  String get subSubcategoryGarmentBags;

  /// No description provided for @subSubcategoryTravelAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Aksesuarları'**
  String get subSubcategoryTravelAccessories;

  /// No description provided for @subSubcategoryBriefcases.
  ///
  /// In tr, this message translates to:
  /// **'Evrak Çantaları'**
  String get subSubcategoryBriefcases;

  /// No description provided for @subSubcategoryLaptopBags.
  ///
  /// In tr, this message translates to:
  /// **'Laptop Çantaları'**
  String get subSubcategoryLaptopBags;

  /// No description provided for @subSubcategoryMessengerBags.
  ///
  /// In tr, this message translates to:
  /// **'Postacı Çantaları'**
  String get subSubcategoryMessengerBags;

  /// No description provided for @subSubcategoryPortfolioBags.
  ///
  /// In tr, this message translates to:
  /// **'Portföy Çantalar'**
  String get subSubcategoryPortfolioBags;

  /// No description provided for @subSubcategoryBusinessTotes.
  ///
  /// In tr, this message translates to:
  /// **'İş Çantaları'**
  String get subSubcategoryBusinessTotes;

  /// No description provided for @subSubcategoryGymBags.
  ///
  /// In tr, this message translates to:
  /// **'Spor Salonu Çantaları'**
  String get subSubcategoryGymBags;

  /// No description provided for @subSubcategorySportsDuffelBags.
  ///
  /// In tr, this message translates to:
  /// **'Spor Çantaları'**
  String get subSubcategorySportsDuffelBags;

  /// No description provided for @subSubcategoryEquipmentBags.
  ///
  /// In tr, this message translates to:
  /// **'Ekipman Çantaları'**
  String get subSubcategoryEquipmentBags;

  /// No description provided for @subSubcategoryYogaBags.
  ///
  /// In tr, this message translates to:
  /// **'Yoga Çantaları'**
  String get subSubcategoryYogaBags;

  /// No description provided for @subSubcategorySwimmingBags.
  ///
  /// In tr, this message translates to:
  /// **'Yüzme Çantaları'**
  String get subSubcategorySwimmingBags;

  /// No description provided for @subSubcategoryWalletsSmall.
  ///
  /// In tr, this message translates to:
  /// **'Cüzdanlar'**
  String get subSubcategoryWalletsSmall;

  /// No description provided for @subSubcategoryCardHolders.
  ///
  /// In tr, this message translates to:
  /// **'Kart Kılıfları'**
  String get subSubcategoryCardHolders;

  /// No description provided for @subSubcategoryCoinPurses.
  ///
  /// In tr, this message translates to:
  /// **'Bozuk Para Cüzdanları'**
  String get subSubcategoryCoinPurses;

  /// No description provided for @subSubcategoryKeyCases.
  ///
  /// In tr, this message translates to:
  /// **'Anahtar Kılıfları'**
  String get subSubcategoryKeyCases;

  /// No description provided for @subSubcategoryPhoneCasesSmall.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Kılıfları'**
  String get subSubcategoryPhoneCasesSmall;

  /// No description provided for @subSubcategoryPassportHolders.
  ///
  /// In tr, this message translates to:
  /// **'Pasaport Kılıfları'**
  String get subSubcategoryPassportHolders;

  /// No description provided for @subSubcategoryCameraBags.
  ///
  /// In tr, this message translates to:
  /// **'Kamera Çantaları'**
  String get subSubcategoryCameraBags;

  /// No description provided for @subSubcategoryDiaperBags.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Çantaları'**
  String get subSubcategoryDiaperBags;

  /// No description provided for @subSubcategoryLunchBags.
  ///
  /// In tr, this message translates to:
  /// **'Beslenme Çantaları'**
  String get subSubcategoryLunchBags;

  /// No description provided for @subSubcategoryToolBags.
  ///
  /// In tr, this message translates to:
  /// **'Alet Çantaları'**
  String get subSubcategoryToolBags;

  /// No description provided for @subSubcategoryCosmeticBags.
  ///
  /// In tr, this message translates to:
  /// **'Kozmetik Çantaları'**
  String get subSubcategoryCosmeticBags;

  /// No description provided for @subSubcategoryBeachBags.
  ///
  /// In tr, this message translates to:
  /// **'Plaj Çantaları'**
  String get subSubcategoryBeachBags;

  /// No description provided for @subSubcategorySmartphones.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Telefonlar'**
  String get subSubcategorySmartphones;

  /// No description provided for @subSubcategoryPhoneCasesElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Kılıfları'**
  String get subSubcategoryPhoneCasesElectronics;

  /// No description provided for @subSubcategoryScreenProtectors.
  ///
  /// In tr, this message translates to:
  /// **'Ekran Koruyucuları'**
  String get subSubcategoryScreenProtectors;

  /// No description provided for @subSubcategoryChargers.
  ///
  /// In tr, this message translates to:
  /// **'Şarj Cihazları'**
  String get subSubcategoryChargers;

  /// No description provided for @subSubcategoryPowerBanks.
  ///
  /// In tr, this message translates to:
  /// **'Power Bank'**
  String get subSubcategoryPowerBanks;

  /// No description provided for @subSubcategoryPhoneStands.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Standları'**
  String get subSubcategoryPhoneStands;

  /// No description provided for @subSubcategoryWirelessChargers.
  ///
  /// In tr, this message translates to:
  /// **'Kablosuz Şarj Cihazları'**
  String get subSubcategoryWirelessChargers;

  /// No description provided for @subSubcategoryLaptops.
  ///
  /// In tr, this message translates to:
  /// **'Laptop\'lar'**
  String get subSubcategoryLaptops;

  /// No description provided for @subSubcategoryDesktopComputers.
  ///
  /// In tr, this message translates to:
  /// **'Masaüstü Bilgisayarlar'**
  String get subSubcategoryDesktopComputers;

  /// No description provided for @subSubcategoryTablets.
  ///
  /// In tr, this message translates to:
  /// **'Tabletler'**
  String get subSubcategoryTablets;

  /// No description provided for @subSubcategoryMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Monitörler'**
  String get subSubcategoryMonitors;

  /// No description provided for @subSubcategoryKeyboards.
  ///
  /// In tr, this message translates to:
  /// **'Klavyeler'**
  String get subSubcategoryKeyboards;

  /// No description provided for @subSubcategoryMice.
  ///
  /// In tr, this message translates to:
  /// **'Fare'**
  String get subSubcategoryMice;

  /// No description provided for @subSubcategoryLaptopAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Laptop Aksesuarları'**
  String get subSubcategoryLaptopAccessories;

  /// No description provided for @subSubcategoryComputerComponents.
  ///
  /// In tr, this message translates to:
  /// **'Bilgisayar Bileşenleri'**
  String get subSubcategoryComputerComponents;

  /// No description provided for @subSubcategorySmartTVs.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı TV\'ler'**
  String get subSubcategorySmartTVs;

  /// No description provided for @subSubcategoryProjectors.
  ///
  /// In tr, this message translates to:
  /// **'Projektörler'**
  String get subSubcategoryProjectors;

  /// No description provided for @subSubcategoryStreamingDevices.
  ///
  /// In tr, this message translates to:
  /// **'Streaming Cihazları'**
  String get subSubcategoryStreamingDevices;

  /// No description provided for @subSubcategoryTVMountsStands.
  ///
  /// In tr, this message translates to:
  /// **'TV Askı ve Standları'**
  String get subSubcategoryTVMountsStands;

  /// No description provided for @subSubcategoryHomeTheaterSystems.
  ///
  /// In tr, this message translates to:
  /// **'Ev Sinema Sistemleri'**
  String get subSubcategoryHomeTheaterSystems;

  /// No description provided for @subSubcategoryTVCablesAccessories.
  ///
  /// In tr, this message translates to:
  /// **'TV Kablo ve Aksesuarları'**
  String get subSubcategoryTVCablesAccessories;

  /// No description provided for @subSubcategoryRemoteControls.
  ///
  /// In tr, this message translates to:
  /// **'Uzaktan Kumandalar'**
  String get subSubcategoryRemoteControls;

  /// No description provided for @subSubcategoryTVAntennas.
  ///
  /// In tr, this message translates to:
  /// **'TV Antenleri'**
  String get subSubcategoryTVAntennas;

  /// No description provided for @subSubcategoryMediaPlayers.
  ///
  /// In tr, this message translates to:
  /// **'Medya Oynatıcıları'**
  String get subSubcategoryMediaPlayers;

  /// No description provided for @subSubcategoryHeadphones.
  ///
  /// In tr, this message translates to:
  /// **'Kulaklıklar'**
  String get subSubcategoryHeadphones;

  /// No description provided for @subSubcategoryEarbuds.
  ///
  /// In tr, this message translates to:
  /// **'Kulaklık'**
  String get subSubcategoryEarbuds;

  /// No description provided for @subSubcategorySpeakers.
  ///
  /// In tr, this message translates to:
  /// **'Hoparlörler'**
  String get subSubcategorySpeakers;

  /// No description provided for @subSubcategorySoundSystems.
  ///
  /// In tr, this message translates to:
  /// **'Ses Sistemleri'**
  String get subSubcategorySoundSystems;

  /// No description provided for @subSubcategorySoundbars.
  ///
  /// In tr, this message translates to:
  /// **'Soundbar'**
  String get subSubcategorySoundbars;

  /// No description provided for @subSubcategoryMicrophones.
  ///
  /// In tr, this message translates to:
  /// **'Mikrofonlar'**
  String get subSubcategoryMicrophones;

  /// No description provided for @subSubcategoryAmplifiers.
  ///
  /// In tr, this message translates to:
  /// **'Amfiler'**
  String get subSubcategoryAmplifiers;

  /// No description provided for @subSubcategoryTurntables.
  ///
  /// In tr, this message translates to:
  /// **'Pikap'**
  String get subSubcategoryTurntables;

  /// No description provided for @subSubcategoryAudioCables.
  ///
  /// In tr, this message translates to:
  /// **'Ses Kabloları'**
  String get subSubcategoryAudioCables;

  /// No description provided for @subSubcategoryGamingConsoles.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Konsolları'**
  String get subSubcategoryGamingConsoles;

  /// No description provided for @subSubcategoryVideoGames.
  ///
  /// In tr, this message translates to:
  /// **'Video Oyunları'**
  String get subSubcategoryVideoGames;

  /// No description provided for @subSubcategoryGamingControllers.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Kumandaları'**
  String get subSubcategoryGamingControllers;

  /// No description provided for @subSubcategoryGamingHeadsets.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Kulaklıkları'**
  String get subSubcategoryGamingHeadsets;

  /// No description provided for @subSubcategoryGamingChairs.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Koltukları'**
  String get subSubcategoryGamingChairs;

  /// No description provided for @subSubcategoryVRHeadsets.
  ///
  /// In tr, this message translates to:
  /// **'VR Gözlükleri'**
  String get subSubcategoryVRHeadsets;

  /// No description provided for @subSubcategoryGamingAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Aksesuarları'**
  String get subSubcategoryGamingAccessories;

  /// No description provided for @subSubcategorySmartSpeakers.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Hoparlörler'**
  String get subSubcategorySmartSpeakers;

  /// No description provided for @subSubcategorySmartLights.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Aydınlatma'**
  String get subSubcategorySmartLights;

  /// No description provided for @subSubcategorySmartPlugs.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Prizler'**
  String get subSubcategorySmartPlugs;

  /// No description provided for @subSubcategorySecurityCameras.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Kameraları'**
  String get subSubcategorySecurityCameras;

  /// No description provided for @subSubcategorySmartThermostats.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Termostatlar'**
  String get subSubcategorySmartThermostats;

  /// No description provided for @subSubcategorySmartLocks.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Kilitler'**
  String get subSubcategorySmartLocks;

  /// No description provided for @subSubcategoryHomeAutomation.
  ///
  /// In tr, this message translates to:
  /// **'Ev Otomasyonu'**
  String get subSubcategoryHomeAutomation;

  /// No description provided for @subSubcategoryDigitalCameras.
  ///
  /// In tr, this message translates to:
  /// **'Dijital Kameralar'**
  String get subSubcategoryDigitalCameras;

  /// No description provided for @subSubcategoryDSLRCameras.
  ///
  /// In tr, this message translates to:
  /// **'DSLR Kameralar'**
  String get subSubcategoryDSLRCameras;

  /// No description provided for @subSubcategoryActionCameras.
  ///
  /// In tr, this message translates to:
  /// **'Aksiyon Kameraları'**
  String get subSubcategoryActionCameras;

  /// No description provided for @subSubcategoryCameraLenses.
  ///
  /// In tr, this message translates to:
  /// **'Kamera Lensleri'**
  String get subSubcategoryCameraLenses;

  /// No description provided for @subSubcategoryTripods.
  ///
  /// In tr, this message translates to:
  /// **'Tripodlar'**
  String get subSubcategoryTripods;

  /// No description provided for @subSubcategoryCameraAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Kamera Aksesuarları'**
  String get subSubcategoryCameraAccessories;

  /// No description provided for @subSubcategoryPhotographyEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğrafçılık Ekipmanları'**
  String get subSubcategoryPhotographyEquipment;

  /// No description provided for @subSubcategorySmartwatchesWearable.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Saatler'**
  String get subSubcategorySmartwatchesWearable;

  /// No description provided for @subSubcategoryFitnessTrackers.
  ///
  /// In tr, this message translates to:
  /// **'Fitness Takipçileri'**
  String get subSubcategoryFitnessTrackers;

  /// No description provided for @subSubcategorySmartGlasses.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Gözlükler'**
  String get subSubcategorySmartGlasses;

  /// No description provided for @subSubcategoryHealthMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık Monitörleri'**
  String get subSubcategoryHealthMonitors;

  /// No description provided for @subSubcategoryWearableAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Giyilebilir Aksesuarlar'**
  String get subSubcategoryWearableAccessories;

  /// No description provided for @subSubcategoryKitchenAppliancesElectronics.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Aletleri'**
  String get subSubcategoryKitchenAppliancesElectronics;

  /// No description provided for @subSubcategoryLaundryAppliances.
  ///
  /// In tr, this message translates to:
  /// **'Çamaşır Makineleri'**
  String get subSubcategoryLaundryAppliances;

  /// No description provided for @subSubcategoryCleaningAppliances.
  ///
  /// In tr, this message translates to:
  /// **'Temizlik Aletleri'**
  String get subSubcategoryCleaningAppliances;

  /// No description provided for @subSubcategoryAirConditioning.
  ///
  /// In tr, this message translates to:
  /// **'Klima'**
  String get subSubcategoryAirConditioning;

  /// No description provided for @subSubcategoryHeating.
  ///
  /// In tr, this message translates to:
  /// **'Isıtma'**
  String get subSubcategoryHeating;

  /// No description provided for @subSubcategorySmallAppliances.
  ///
  /// In tr, this message translates to:
  /// **'Küçük Ev Aletleri'**
  String get subSubcategorySmallAppliances;

  /// No description provided for @subSubcategoryHairDryers.
  ///
  /// In tr, this message translates to:
  /// **'Saç Kurutma Makineleri'**
  String get subSubcategoryHairDryers;

  /// No description provided for @subSubcategoryHairStraighteners.
  ///
  /// In tr, this message translates to:
  /// **'Saç Düzleştiricileri'**
  String get subSubcategoryHairStraighteners;

  /// No description provided for @subSubcategoryElectricShavers.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Tıraş Makineleri'**
  String get subSubcategoryElectricShavers;

  /// No description provided for @subSubcategoryElectricToothbrushes.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Diş Fırçaları'**
  String get subSubcategoryElectricToothbrushes;

  /// No description provided for @subSubcategoryBeautyDevices.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik Cihazları'**
  String get subSubcategoryBeautyDevices;

  /// No description provided for @subSubcategoryPersonalHealthMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Sağlık Monitörleri'**
  String get subSubcategoryPersonalHealthMonitors;

  /// No description provided for @subSubcategoryCardioEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Kardiyo Ekipmanları'**
  String get subSubcategoryCardioEquipment;

  /// No description provided for @subSubcategoryStrengthTraining.
  ///
  /// In tr, this message translates to:
  /// **'Güç Antrenmanı'**
  String get subSubcategoryStrengthTraining;

  /// No description provided for @subSubcategoryYogaEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Yoga Ekipmanları'**
  String get subSubcategoryYogaEquipment;

  /// No description provided for @subSubcategoryPilatesEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Pilates Ekipmanları'**
  String get subSubcategoryPilatesEquipment;

  /// No description provided for @subSubcategoryHomeGym.
  ///
  /// In tr, this message translates to:
  /// **'Ev Jimnastiği'**
  String get subSubcategoryHomeGym;

  /// No description provided for @subSubcategoryExerciseAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Egzersiz Aksesuarları'**
  String get subSubcategoryExerciseAccessories;

  /// No description provided for @subSubcategoryRecoveryEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Toparlanma Ekipmanları'**
  String get subSubcategoryRecoveryEquipment;

  /// No description provided for @subSubcategoryFootball.
  ///
  /// In tr, this message translates to:
  /// **'Futbol'**
  String get subSubcategoryFootball;

  /// No description provided for @subSubcategoryBasketball.
  ///
  /// In tr, this message translates to:
  /// **'Basketbol'**
  String get subSubcategoryBasketball;

  /// No description provided for @subSubcategoryBaseball.
  ///
  /// In tr, this message translates to:
  /// **'Beyzbol'**
  String get subSubcategoryBaseball;

  /// No description provided for @subSubcategoryVolleyball.
  ///
  /// In tr, this message translates to:
  /// **'Voleybol'**
  String get subSubcategoryVolleyball;

  /// No description provided for @subSubcategoryTennis.
  ///
  /// In tr, this message translates to:
  /// **'Tenis'**
  String get subSubcategoryTennis;

  /// No description provided for @subSubcategoryCricket.
  ///
  /// In tr, this message translates to:
  /// **'Kriket'**
  String get subSubcategoryCricket;

  /// No description provided for @subSubcategoryAmericanFootball.
  ///
  /// In tr, this message translates to:
  /// **'Amerikan Futbolu'**
  String get subSubcategoryAmericanFootball;

  /// No description provided for @subSubcategoryGolf.
  ///
  /// In tr, this message translates to:
  /// **'Golf'**
  String get subSubcategoryGolf;

  /// No description provided for @subSubcategoryTableTennis.
  ///
  /// In tr, this message translates to:
  /// **'Masa Tenisi'**
  String get subSubcategoryTableTennis;

  /// No description provided for @subSubcategoryBadminton.
  ///
  /// In tr, this message translates to:
  /// **'Badminton'**
  String get subSubcategoryBadminton;

  /// No description provided for @subSubcategorySwimming.
  ///
  /// In tr, this message translates to:
  /// **'Yüzme'**
  String get subSubcategorySwimming;

  /// No description provided for @subSubcategorySurfing.
  ///
  /// In tr, this message translates to:
  /// **'Sörf'**
  String get subSubcategorySurfing;

  /// No description provided for @subSubcategoryKayaking.
  ///
  /// In tr, this message translates to:
  /// **'Kano'**
  String get subSubcategoryKayaking;

  /// No description provided for @subSubcategoryDiving.
  ///
  /// In tr, this message translates to:
  /// **'Dalış'**
  String get subSubcategoryDiving;

  /// No description provided for @subSubcategoryWaterSkiing.
  ///
  /// In tr, this message translates to:
  /// **'Su Kayağı'**
  String get subSubcategoryWaterSkiing;

  /// No description provided for @subSubcategoryFishing.
  ///
  /// In tr, this message translates to:
  /// **'Balıkçılık'**
  String get subSubcategoryFishing;

  /// No description provided for @subSubcategoryBoating.
  ///
  /// In tr, this message translates to:
  /// **'Teknecilik'**
  String get subSubcategoryBoating;

  /// No description provided for @subSubcategoryWaterSafety.
  ///
  /// In tr, this message translates to:
  /// **'Su Güvenliği'**
  String get subSubcategoryWaterSafety;

  /// No description provided for @subSubcategoryCampingGear.
  ///
  /// In tr, this message translates to:
  /// **'Kamp Malzemeleri'**
  String get subSubcategoryCampingGear;

  /// No description provided for @subSubcategoryHikingEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Trekking Ekipmanları'**
  String get subSubcategoryHikingEquipment;

  /// No description provided for @subSubcategoryBackpacking.
  ///
  /// In tr, this message translates to:
  /// **'Sırt Çantalı Seyahat'**
  String get subSubcategoryBackpacking;

  /// No description provided for @subSubcategoryClimbingGear.
  ///
  /// In tr, this message translates to:
  /// **'Tırmanış Malzemeleri'**
  String get subSubcategoryClimbingGear;

  /// No description provided for @subSubcategoryOutdoorClothing.
  ///
  /// In tr, this message translates to:
  /// **'Outdoor Giyim'**
  String get subSubcategoryOutdoorClothing;

  /// No description provided for @subSubcategoryNavigation.
  ///
  /// In tr, this message translates to:
  /// **'Navigasyon'**
  String get subSubcategoryNavigation;

  /// No description provided for @subSubcategorySurvivalGear.
  ///
  /// In tr, this message translates to:
  /// **'Hayatta Kalma Ekipmanları'**
  String get subSubcategorySurvivalGear;

  /// No description provided for @subSubcategorySkiing.
  ///
  /// In tr, this message translates to:
  /// **'Kayak'**
  String get subSubcategorySkiing;

  /// No description provided for @subSubcategorySnowboarding.
  ///
  /// In tr, this message translates to:
  /// **'Snowboard'**
  String get subSubcategorySnowboarding;

  /// No description provided for @subSubcategoryIceSkating.
  ///
  /// In tr, this message translates to:
  /// **'Buz Pateni'**
  String get subSubcategoryIceSkating;

  /// No description provided for @subSubcategoryWinterClothing.
  ///
  /// In tr, this message translates to:
  /// **'Kış Giyim'**
  String get subSubcategoryWinterClothing;

  /// No description provided for @subSubcategorySnowEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Kar Ekipmanları'**
  String get subSubcategorySnowEquipment;

  /// No description provided for @subSubcategoryWinterAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Kış Aksesuarları'**
  String get subSubcategoryWinterAccessories;

  /// No description provided for @subSubcategoryBicycles.
  ///
  /// In tr, this message translates to:
  /// **'Bisikletler'**
  String get subSubcategoryBicycles;

  /// No description provided for @subSubcategoryBikeAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Bisiklet Aksesuarları'**
  String get subSubcategoryBikeAccessories;

  /// No description provided for @subSubcategoryCyclingApparel.
  ///
  /// In tr, this message translates to:
  /// **'Bisiklet Giyim'**
  String get subSubcategoryCyclingApparel;

  /// No description provided for @subSubcategoryBikeMaintenance.
  ///
  /// In tr, this message translates to:
  /// **'Bisiklet Bakımı'**
  String get subSubcategoryBikeMaintenance;

  /// No description provided for @subSubcategoryBikeSafety.
  ///
  /// In tr, this message translates to:
  /// **'Bisiklet Güvenliği'**
  String get subSubcategoryBikeSafety;

  /// No description provided for @subSubcategoryEBikes.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Bisikletler'**
  String get subSubcategoryEBikes;

  /// No description provided for @subSubcategoryRunningShoesAthletics.
  ///
  /// In tr, this message translates to:
  /// **'Koşu Ayakkabıları'**
  String get subSubcategoryRunningShoesAthletics;

  /// No description provided for @subSubcategoryRunningApparel.
  ///
  /// In tr, this message translates to:
  /// **'Koşu Giyim'**
  String get subSubcategoryRunningApparel;

  /// No description provided for @subSubcategoryTrackField.
  ///
  /// In tr, this message translates to:
  /// **'Atletizm'**
  String get subSubcategoryTrackField;

  /// No description provided for @subSubcategoryMarathonGear.
  ///
  /// In tr, this message translates to:
  /// **'Maraton Ekipmanları'**
  String get subSubcategoryMarathonGear;

  /// No description provided for @subSubcategoryRunningAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Koşu Aksesuarları'**
  String get subSubcategoryRunningAccessories;

  /// No description provided for @subSubcategoryPerformanceMonitoring.
  ///
  /// In tr, this message translates to:
  /// **'Performans Takibi'**
  String get subSubcategoryPerformanceMonitoring;

  /// No description provided for @subSubcategorySportsBags.
  ///
  /// In tr, this message translates to:
  /// **'Spor Çantaları'**
  String get subSubcategorySportsBags;

  /// No description provided for @subSubcategoryProtectiveGear.
  ///
  /// In tr, this message translates to:
  /// **'Koruyucu Ekipmanlar'**
  String get subSubcategoryProtectiveGear;

  /// No description provided for @subSubcategorySportsNutrition.
  ///
  /// In tr, this message translates to:
  /// **'Spor Beslenmesi'**
  String get subSubcategorySportsNutrition;

  /// No description provided for @subSubcategoryHydration.
  ///
  /// In tr, this message translates to:
  /// **'Hidrasyon'**
  String get subSubcategoryHydration;

  /// No description provided for @subSubcategorySportsTechnology.
  ///
  /// In tr, this message translates to:
  /// **'Spor Teknolojisi'**
  String get subSubcategorySportsTechnology;

  /// No description provided for @subSubcategoryFanGear.
  ///
  /// In tr, this message translates to:
  /// **'Taraftar Ürünleri'**
  String get subSubcategoryFanGear;

  /// No description provided for @subSubcategoryAthleticTopsWear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Üstleri'**
  String get subSubcategoryAthleticTopsWear;

  /// No description provided for @subSubcategoryAthleticBottomsWear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Altları'**
  String get subSubcategoryAthleticBottomsWear;

  /// No description provided for @subSubcategorySportsBrasWear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Sütyenleri'**
  String get subSubcategorySportsBrasWear;

  /// No description provided for @subSubcategoryAthleticShoes.
  ///
  /// In tr, this message translates to:
  /// **'Spor Ayakkabıları'**
  String get subSubcategoryAthleticShoes;

  /// No description provided for @subSubcategorySportsAccessoriesWear.
  ///
  /// In tr, this message translates to:
  /// **'Spor Aksesuarları'**
  String get subSubcategorySportsAccessoriesWear;

  /// No description provided for @subSubcategoryTeamJerseys.
  ///
  /// In tr, this message translates to:
  /// **'Takım Formaları'**
  String get subSubcategoryTeamJerseys;

  /// No description provided for @subSubcategoryFictionBooks.
  ///
  /// In tr, this message translates to:
  /// **'Kurgu Kitapları'**
  String get subSubcategoryFictionBooks;

  /// No description provided for @subSubcategoryNonFictionBooks.
  ///
  /// In tr, this message translates to:
  /// **'Kurgu Dışı Kitaplar'**
  String get subSubcategoryNonFictionBooks;

  /// No description provided for @subSubcategoryEducationalBooksLiterature.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Kitapları'**
  String get subSubcategoryEducationalBooksLiterature;

  /// No description provided for @subSubcategoryChildrensBooks.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk Kitapları'**
  String get subSubcategoryChildrensBooks;

  /// No description provided for @subSubcategoryReferenceBooks.
  ///
  /// In tr, this message translates to:
  /// **'Referans Kitapları'**
  String get subSubcategoryReferenceBooks;

  /// No description provided for @subSubcategoryMagazines.
  ///
  /// In tr, this message translates to:
  /// **'Dergiler'**
  String get subSubcategoryMagazines;

  /// No description provided for @subSubcategoryComics.
  ///
  /// In tr, this message translates to:
  /// **'Çizgi Romanlar'**
  String get subSubcategoryComics;

  /// No description provided for @subSubcategoryEBooks.
  ///
  /// In tr, this message translates to:
  /// **'E-Kitaplar'**
  String get subSubcategoryEBooks;

  /// No description provided for @subSubcategoryNotebooks.
  ///
  /// In tr, this message translates to:
  /// **'Defterler'**
  String get subSubcategoryNotebooks;

  /// No description provided for @subSubcategoryBinders.
  ///
  /// In tr, this message translates to:
  /// **'Klasörler'**
  String get subSubcategoryBinders;

  /// No description provided for @subSubcategoryFolders.
  ///
  /// In tr, this message translates to:
  /// **'Dosyalar'**
  String get subSubcategoryFolders;

  /// No description provided for @subSubcategoryDeskAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Masa Aksesuarları'**
  String get subSubcategoryDeskAccessories;

  /// No description provided for @subSubcategoryCalculators.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Makineleri'**
  String get subSubcategoryCalculators;

  /// No description provided for @subSubcategoryLabels.
  ///
  /// In tr, this message translates to:
  /// **'Etiketler'**
  String get subSubcategoryLabels;

  /// No description provided for @subSubcategoryStaplers.
  ///
  /// In tr, this message translates to:
  /// **'Zımba Makineleri'**
  String get subSubcategoryStaplers;

  /// No description provided for @subSubcategoryOrganizers.
  ///
  /// In tr, this message translates to:
  /// **'Organizer\'lar'**
  String get subSubcategoryOrganizers;

  /// No description provided for @subSubcategoryDrawingSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Çizim Malzemeleri'**
  String get subSubcategoryDrawingSupplies;

  /// No description provided for @subSubcategoryPaintingSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Boyama Malzemeleri'**
  String get subSubcategoryPaintingSupplies;

  /// No description provided for @subSubcategoryCraftMaterials.
  ///
  /// In tr, this message translates to:
  /// **'El Sanatları Malzemeleri'**
  String get subSubcategoryCraftMaterials;

  /// No description provided for @subSubcategoryScrapbooking.
  ///
  /// In tr, this message translates to:
  /// **'Scrapbooking'**
  String get subSubcategoryScrapbooking;

  /// No description provided for @subSubcategorySewingSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Dikiş Malzemeleri'**
  String get subSubcategorySewingSupplies;

  /// No description provided for @subSubcategoryJewelryMaking.
  ///
  /// In tr, this message translates to:
  /// **'Mücevher Yapımı'**
  String get subSubcategoryJewelryMaking;

  /// No description provided for @subSubcategoryModelBuilding.
  ///
  /// In tr, this message translates to:
  /// **'Model Yapımı'**
  String get subSubcategoryModelBuilding;

  /// No description provided for @subSubcategoryPens.
  ///
  /// In tr, this message translates to:
  /// **'Kalemler'**
  String get subSubcategoryPens;

  /// No description provided for @subSubcategoryPencils.
  ///
  /// In tr, this message translates to:
  /// **'Kurşun Kalemler'**
  String get subSubcategoryPencils;

  /// No description provided for @subSubcategoryMarkers.
  ///
  /// In tr, this message translates to:
  /// **'Keçeli Kalemler'**
  String get subSubcategoryMarkers;

  /// No description provided for @subSubcategoryHighlighters.
  ///
  /// In tr, this message translates to:
  /// **'Fosforlu Kalemler'**
  String get subSubcategoryHighlighters;

  /// No description provided for @subSubcategoryFountainPens.
  ///
  /// In tr, this message translates to:
  /// **'Dolma Kalemler'**
  String get subSubcategoryFountainPens;

  /// No description provided for @subSubcategoryMechanicalPencils.
  ///
  /// In tr, this message translates to:
  /// **'Mekanik Kurşun Kalemler'**
  String get subSubcategoryMechanicalPencils;

  /// No description provided for @subSubcategoryErasers.
  ///
  /// In tr, this message translates to:
  /// **'Silgiler'**
  String get subSubcategoryErasers;

  /// No description provided for @subSubcategoryCopyPaper.
  ///
  /// In tr, this message translates to:
  /// **'Fotokopi Kağıdı'**
  String get subSubcategoryCopyPaper;

  /// No description provided for @subSubcategorySpecialtyPaper.
  ///
  /// In tr, this message translates to:
  /// **'Özel Kağıtlar'**
  String get subSubcategorySpecialtyPaper;

  /// No description provided for @subSubcategoryCardstock.
  ///
  /// In tr, this message translates to:
  /// **'Karton'**
  String get subSubcategoryCardstock;

  /// No description provided for @subSubcategoryEnvelopes.
  ///
  /// In tr, this message translates to:
  /// **'Zarflar'**
  String get subSubcategoryEnvelopes;

  /// No description provided for @subSubcategoryStickyNotes.
  ///
  /// In tr, this message translates to:
  /// **'Yapışkan Notlar'**
  String get subSubcategoryStickyNotes;

  /// No description provided for @subSubcategoryIndexCards.
  ///
  /// In tr, this message translates to:
  /// **'Fişler'**
  String get subSubcategoryIndexCards;

  /// No description provided for @subSubcategoryConstructionPaper.
  ///
  /// In tr, this message translates to:
  /// **'Renkli Karton'**
  String get subSubcategoryConstructionPaper;

  /// No description provided for @subSubcategoryLearningGames.
  ///
  /// In tr, this message translates to:
  /// **'Öğrenme Oyunları'**
  String get subSubcategoryLearningGames;

  /// No description provided for @subSubcategoryFlashCardsEducational.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Kartları'**
  String get subSubcategoryFlashCardsEducational;

  /// No description provided for @subSubcategoryEducationalToysStationery.
  ///
  /// In tr, this message translates to:
  /// **'Eğitici Oyuncaklar'**
  String get subSubcategoryEducationalToysStationery;

  /// No description provided for @subSubcategoryScienceKitsStationery.
  ///
  /// In tr, this message translates to:
  /// **'Bilim Setleri'**
  String get subSubcategoryScienceKitsStationery;

  /// No description provided for @subSubcategoryMathTools.
  ///
  /// In tr, this message translates to:
  /// **'Matematik Araçları'**
  String get subSubcategoryMathTools;

  /// No description provided for @subSubcategoryLanguageLearning.
  ///
  /// In tr, this message translates to:
  /// **'Dil Öğrenimi'**
  String get subSubcategoryLanguageLearning;

  /// No description provided for @subSubcategoryBoardGamesHobby.
  ///
  /// In tr, this message translates to:
  /// **'Masa Oyunları'**
  String get subSubcategoryBoardGamesHobby;

  /// No description provided for @subSubcategoryPuzzlesHobby.
  ///
  /// In tr, this message translates to:
  /// **'Yapbozlar'**
  String get subSubcategoryPuzzlesHobby;

  /// No description provided for @subSubcategoryTradingCards.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon Kartları'**
  String get subSubcategoryTradingCards;

  /// No description provided for @subSubcategoryCollectibles.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon Eşyaları'**
  String get subSubcategoryCollectibles;

  /// No description provided for @subSubcategoryModelKits.
  ///
  /// In tr, this message translates to:
  /// **'Model Setleri'**
  String get subSubcategoryModelKits;

  /// No description provided for @subSubcategoryGamingAccessoriesHobby.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Aksesuarları'**
  String get subSubcategoryGamingAccessoriesHobby;

  /// No description provided for @subSubcategoryStringInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Telli Çalgılar'**
  String get subSubcategoryStringInstruments;

  /// No description provided for @subSubcategoryWindInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Nefesli Çalgılar'**
  String get subSubcategoryWindInstruments;

  /// No description provided for @subSubcategoryPercussion.
  ///
  /// In tr, this message translates to:
  /// **'Vurmalı Çalgılar'**
  String get subSubcategoryPercussion;

  /// No description provided for @subSubcategoryElectronicInstruments.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik Çalgılar'**
  String get subSubcategoryElectronicInstruments;

  /// No description provided for @subSubcategoryMusicAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Müzik Aksesuarları'**
  String get subSubcategoryMusicAccessories;

  /// No description provided for @subSubcategorySheetMusic.
  ///
  /// In tr, this message translates to:
  /// **'Nota Kitapları'**
  String get subSubcategorySheetMusic;

  /// No description provided for @subSubcategoryHammers.
  ///
  /// In tr, this message translates to:
  /// **'Çekiçler'**
  String get subSubcategoryHammers;

  /// No description provided for @subSubcategoryScrewdrivers.
  ///
  /// In tr, this message translates to:
  /// **'Tornavidalar'**
  String get subSubcategoryScrewdrivers;

  /// No description provided for @subSubcategoryWrenches.
  ///
  /// In tr, this message translates to:
  /// **'İngiliz Anahtarları'**
  String get subSubcategoryWrenches;

  /// No description provided for @subSubcategoryPliers.
  ///
  /// In tr, this message translates to:
  /// **'Pense'**
  String get subSubcategoryPliers;

  /// No description provided for @subSubcategorySaws.
  ///
  /// In tr, this message translates to:
  /// **'Testereler'**
  String get subSubcategorySaws;

  /// No description provided for @subSubcategoryChisels.
  ///
  /// In tr, this message translates to:
  /// **'Keski'**
  String get subSubcategoryChisels;

  /// No description provided for @subSubcategoryUtilityKnives.
  ///
  /// In tr, this message translates to:
  /// **'Maket Bıçakları'**
  String get subSubcategoryUtilityKnives;

  /// No description provided for @subSubcategoryHandToolSets.
  ///
  /// In tr, this message translates to:
  /// **'El Aleti Setleri'**
  String get subSubcategoryHandToolSets;

  /// No description provided for @subSubcategoryDrills.
  ///
  /// In tr, this message translates to:
  /// **'Matkap'**
  String get subSubcategoryDrills;

  /// No description provided for @subSubcategoryPowerSaws.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Testere'**
  String get subSubcategoryPowerSaws;

  /// No description provided for @subSubcategorySanders.
  ///
  /// In tr, this message translates to:
  /// **'Zımpara Makineleri'**
  String get subSubcategorySanders;

  /// No description provided for @subSubcategoryGrinders.
  ///
  /// In tr, this message translates to:
  /// **'Taşlama Makineleri'**
  String get subSubcategoryGrinders;

  /// No description provided for @subSubcategoryRouters.
  ///
  /// In tr, this message translates to:
  /// **'Router'**
  String get subSubcategoryRouters;

  /// No description provided for @subSubcategoryNailGuns.
  ///
  /// In tr, this message translates to:
  /// **'Çivi Tabancaları'**
  String get subSubcategoryNailGuns;

  /// No description provided for @subSubcategoryImpactDrivers.
  ///
  /// In tr, this message translates to:
  /// **'Darbe Vidalama Makineleri'**
  String get subSubcategoryImpactDrivers;

  /// No description provided for @subSubcategoryMultiTools.
  ///
  /// In tr, this message translates to:
  /// **'Çok Amaçlı Aletler'**
  String get subSubcategoryMultiTools;

  /// No description provided for @subSubcategoryScrews.
  ///
  /// In tr, this message translates to:
  /// **'Vidalar'**
  String get subSubcategoryScrews;

  /// No description provided for @subSubcategoryBoltsNuts.
  ///
  /// In tr, this message translates to:
  /// **'Civata ve Somunlar'**
  String get subSubcategoryBoltsNuts;

  /// No description provided for @subSubcategoryNails.
  ///
  /// In tr, this message translates to:
  /// **'Çiviler'**
  String get subSubcategoryNails;

  /// No description provided for @subSubcategoryWashers.
  ///
  /// In tr, this message translates to:
  /// **'Rondela'**
  String get subSubcategoryWashers;

  /// No description provided for @subSubcategoryAnchors.
  ///
  /// In tr, this message translates to:
  /// **'Dübel'**
  String get subSubcategoryAnchors;

  /// No description provided for @subSubcategoryHinges.
  ///
  /// In tr, this message translates to:
  /// **'Menteşeler'**
  String get subSubcategoryHinges;

  /// No description provided for @subSubcategoryHandlesKnobs.
  ///
  /// In tr, this message translates to:
  /// **'Kulp ve Topuzlar'**
  String get subSubcategoryHandlesKnobs;

  /// No description provided for @subSubcategoryChains.
  ///
  /// In tr, this message translates to:
  /// **'Zincirler'**
  String get subSubcategoryChains;

  /// No description provided for @subSubcategoryWireCable.
  ///
  /// In tr, this message translates to:
  /// **'Kablo ve Tel'**
  String get subSubcategoryWireCable;

  /// No description provided for @subSubcategoryOutletsSwitches.
  ///
  /// In tr, this message translates to:
  /// **'Priz ve Anahtarlar'**
  String get subSubcategoryOutletsSwitches;

  /// No description provided for @subSubcategoryCircuitBreakers.
  ///
  /// In tr, this message translates to:
  /// **'Sigorta'**
  String get subSubcategoryCircuitBreakers;

  /// No description provided for @subSubcategoryLightFixtures.
  ///
  /// In tr, this message translates to:
  /// **'Aydınlatma Armatürleri'**
  String get subSubcategoryLightFixtures;

  /// No description provided for @subSubcategoryElectricalTools.
  ///
  /// In tr, this message translates to:
  /// **'Elektrik Aletleri'**
  String get subSubcategoryElectricalTools;

  /// No description provided for @subSubcategoryExtensionCords.
  ///
  /// In tr, this message translates to:
  /// **'Uzatma Kabloları'**
  String get subSubcategoryExtensionCords;

  /// No description provided for @subSubcategoryPipesFittings.
  ///
  /// In tr, this message translates to:
  /// **'Boru ve Bağlantı Parçaları'**
  String get subSubcategoryPipesFittings;

  /// No description provided for @subSubcategoryValves.
  ///
  /// In tr, this message translates to:
  /// **'Vanalar'**
  String get subSubcategoryValves;

  /// No description provided for @subSubcategoryFaucets.
  ///
  /// In tr, this message translates to:
  /// **'Musluklar'**
  String get subSubcategoryFaucets;

  /// No description provided for @subSubcategoryToiletParts.
  ///
  /// In tr, this message translates to:
  /// **'Klozet Parçaları'**
  String get subSubcategoryToiletParts;

  /// No description provided for @subSubcategoryDrainCleaners.
  ///
  /// In tr, this message translates to:
  /// **'Gider Temizleyicileri'**
  String get subSubcategoryDrainCleaners;

  /// No description provided for @subSubcategoryPipeTools.
  ///
  /// In tr, this message translates to:
  /// **'Boru Aletleri'**
  String get subSubcategoryPipeTools;

  /// No description provided for @subSubcategorySealants.
  ///
  /// In tr, this message translates to:
  /// **'Sızdırmazlık Malzemeleri'**
  String get subSubcategorySealants;

  /// No description provided for @subSubcategoryLumber.
  ///
  /// In tr, this message translates to:
  /// **'Kereste'**
  String get subSubcategoryLumber;

  /// No description provided for @subSubcategoryDrywall.
  ///
  /// In tr, this message translates to:
  /// **'Alçıpan'**
  String get subSubcategoryDrywall;

  /// No description provided for @subSubcategoryInsulation.
  ///
  /// In tr, this message translates to:
  /// **'Yalıtım'**
  String get subSubcategoryInsulation;

  /// No description provided for @subSubcategoryRoofingMaterials.
  ///
  /// In tr, this message translates to:
  /// **'Çatı Malzemeleri'**
  String get subSubcategoryRoofingMaterials;

  /// No description provided for @subSubcategoryFlooring.
  ///
  /// In tr, this message translates to:
  /// **'Döşeme'**
  String get subSubcategoryFlooring;

  /// No description provided for @subSubcategoryConcrete.
  ///
  /// In tr, this message translates to:
  /// **'Beton'**
  String get subSubcategoryConcrete;

  /// No description provided for @subSubcategoryPaint.
  ///
  /// In tr, this message translates to:
  /// **'Boya'**
  String get subSubcategoryPaint;

  /// No description provided for @subSubcategoryWorkGlovesSafety.
  ///
  /// In tr, this message translates to:
  /// **'İş Eldivenleri'**
  String get subSubcategoryWorkGlovesSafety;

  /// No description provided for @subSubcategorySafetyGlassesSafety.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Gözlükleri'**
  String get subSubcategorySafetyGlassesSafety;

  /// No description provided for @subSubcategoryHardHats.
  ///
  /// In tr, this message translates to:
  /// **'Baret'**
  String get subSubcategoryHardHats;

  /// No description provided for @subSubcategoryEarProtection.
  ///
  /// In tr, this message translates to:
  /// **'Kulak Koruyucuları'**
  String get subSubcategoryEarProtection;

  /// No description provided for @subSubcategoryRespirators.
  ///
  /// In tr, this message translates to:
  /// **'Solunum Koruyucuları'**
  String get subSubcategoryRespirators;

  /// No description provided for @subSubcategorySafetyVests.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Yelekleri'**
  String get subSubcategorySafetyVests;

  /// No description provided for @subSubcategoryFirstAidKitsSafety.
  ///
  /// In tr, this message translates to:
  /// **'İlk Yardım Setleri'**
  String get subSubcategoryFirstAidKitsSafety;

  /// No description provided for @subSubcategoryTapeMeasures.
  ///
  /// In tr, this message translates to:
  /// **'Şerit Metre'**
  String get subSubcategoryTapeMeasures;

  /// No description provided for @subSubcategoryLevels.
  ///
  /// In tr, this message translates to:
  /// **'Teraziler'**
  String get subSubcategoryLevels;

  /// No description provided for @subSubcategorySquares.
  ///
  /// In tr, this message translates to:
  /// **'Gönyeler'**
  String get subSubcategorySquares;

  /// No description provided for @subSubcategoryCalipers.
  ///
  /// In tr, this message translates to:
  /// **'Kumpas'**
  String get subSubcategoryCalipers;

  /// No description provided for @subSubcategoryRulers.
  ///
  /// In tr, this message translates to:
  /// **'Cetveller'**
  String get subSubcategoryRulers;

  /// No description provided for @subSubcategoryLaserLevels.
  ///
  /// In tr, this message translates to:
  /// **'Lazer Teraziler'**
  String get subSubcategoryLaserLevels;

  /// No description provided for @subSubcategoryMarkingTools.
  ///
  /// In tr, this message translates to:
  /// **'İşaretleme Aletleri'**
  String get subSubcategoryMarkingTools;

  /// No description provided for @subSubcategoryToolBoxes.
  ///
  /// In tr, this message translates to:
  /// **'Alet Kutuları'**
  String get subSubcategoryToolBoxes;

  /// No description provided for @subSubcategoryToolBagsStorage.
  ///
  /// In tr, this message translates to:
  /// **'Alet Çantaları'**
  String get subSubcategoryToolBagsStorage;

  /// No description provided for @subSubcategoryToolChests.
  ///
  /// In tr, this message translates to:
  /// **'Alet Dolabı'**
  String get subSubcategoryToolChests;

  /// No description provided for @subSubcategoryWorkshopStorage.
  ///
  /// In tr, this message translates to:
  /// **'Atölye Saklama'**
  String get subSubcategoryWorkshopStorage;

  /// No description provided for @subSubcategoryToolOrganizers.
  ///
  /// In tr, this message translates to:
  /// **'Alet Organizerleri'**
  String get subSubcategoryToolOrganizers;

  /// No description provided for @subSubcategoryDogFood.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Maması'**
  String get subSubcategoryDogFood;

  /// No description provided for @subSubcategoryDogToys.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Oyuncakları'**
  String get subSubcategoryDogToys;

  /// No description provided for @subSubcategoryDogBeds.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Yatakları'**
  String get subSubcategoryDogBeds;

  /// No description provided for @subSubcategoryLeashesCollars.
  ///
  /// In tr, this message translates to:
  /// **'Tasma ve Gerdanlık'**
  String get subSubcategoryLeashesCollars;

  /// No description provided for @subSubcategoryDogClothing.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Giysileri'**
  String get subSubcategoryDogClothing;

  /// No description provided for @subSubcategoryDogGrooming.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Bakımı'**
  String get subSubcategoryDogGrooming;

  /// No description provided for @subSubcategoryDogTraining.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Eğitimi'**
  String get subSubcategoryDogTraining;

  /// No description provided for @subSubcategoryDogHealthCare.
  ///
  /// In tr, this message translates to:
  /// **'Köpek Sağlık Bakımı'**
  String get subSubcategoryDogHealthCare;

  /// No description provided for @subSubcategoryCatFood.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Maması'**
  String get subSubcategoryCatFood;

  /// No description provided for @subSubcategoryCatToys.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Oyuncakları'**
  String get subSubcategoryCatToys;

  /// No description provided for @subSubcategoryCatBeds.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Yatakları'**
  String get subSubcategoryCatBeds;

  /// No description provided for @subSubcategoryLitterBoxes.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Kumu ve Kutuları'**
  String get subSubcategoryLitterBoxes;

  /// No description provided for @subSubcategoryCatTrees.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Tırmanma Ağaçları'**
  String get subSubcategoryCatTrees;

  /// No description provided for @subSubcategoryCatGrooming.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Bakımı'**
  String get subSubcategoryCatGrooming;

  /// No description provided for @subSubcategoryCatCarriers.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Taşıma Çantaları'**
  String get subSubcategoryCatCarriers;

  /// No description provided for @subSubcategoryCatHealthCare.
  ///
  /// In tr, this message translates to:
  /// **'Kedi Sağlık Bakımı'**
  String get subSubcategoryCatHealthCare;

  /// No description provided for @subSubcategoryBirdFood.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Yemi'**
  String get subSubcategoryBirdFood;

  /// No description provided for @subSubcategoryBirdCages.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Kafesleri'**
  String get subSubcategoryBirdCages;

  /// No description provided for @subSubcategoryBirdToys.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Oyuncakları'**
  String get subSubcategoryBirdToys;

  /// No description provided for @subSubcategoryBirdPerches.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Tünekleri'**
  String get subSubcategoryBirdPerches;

  /// No description provided for @subSubcategoryBirdHouses.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Evleri'**
  String get subSubcategoryBirdHouses;

  /// No description provided for @subSubcategoryBirdHealthCare.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Sağlık Bakımı'**
  String get subSubcategoryBirdHealthCare;

  /// No description provided for @subSubcategoryBirdAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Kuş Aksesuarları'**
  String get subSubcategoryBirdAccessories;

  /// No description provided for @subSubcategoryFishFood.
  ///
  /// In tr, this message translates to:
  /// **'Balık Yemi'**
  String get subSubcategoryFishFood;

  /// No description provided for @subSubcategoryAquariumTanks.
  ///
  /// In tr, this message translates to:
  /// **'Akvaryum Tankları'**
  String get subSubcategoryAquariumTanks;

  /// No description provided for @subSubcategoryAquariumFilters.
  ///
  /// In tr, this message translates to:
  /// **'Akvaryum Filtreleri'**
  String get subSubcategoryAquariumFilters;

  /// No description provided for @subSubcategoryAquariumDecorations.
  ///
  /// In tr, this message translates to:
  /// **'Akvaryum Dekorasyonları'**
  String get subSubcategoryAquariumDecorations;

  /// No description provided for @subSubcategoryWaterTreatment.
  ///
  /// In tr, this message translates to:
  /// **'Su Arıtma'**
  String get subSubcategoryWaterTreatment;

  /// No description provided for @subSubcategoryAquariumLighting.
  ///
  /// In tr, this message translates to:
  /// **'Akvaryum Aydınlatması'**
  String get subSubcategoryAquariumLighting;

  /// No description provided for @subSubcategoryFishHealthCare.
  ///
  /// In tr, this message translates to:
  /// **'Balık Sağlık Bakımı'**
  String get subSubcategoryFishHealthCare;

  /// No description provided for @subSubcategorySmallAnimalFood.
  ///
  /// In tr, this message translates to:
  /// **'Küçük Hayvan Yemi'**
  String get subSubcategorySmallAnimalFood;

  /// No description provided for @subSubcategoryCagesHabitats.
  ///
  /// In tr, this message translates to:
  /// **'Kafes ve Yaşam Alanları'**
  String get subSubcategoryCagesHabitats;

  /// No description provided for @subSubcategorySmallAnimalToys.
  ///
  /// In tr, this message translates to:
  /// **'Küçük Hayvan Oyuncakları'**
  String get subSubcategorySmallAnimalToys;

  /// No description provided for @subSubcategoryBedding.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Malzemeleri'**
  String get subSubcategoryBedding;

  /// No description provided for @subSubcategoryWaterBottles.
  ///
  /// In tr, this message translates to:
  /// **'Su Şişeleri'**
  String get subSubcategoryWaterBottles;

  /// No description provided for @subSubcategoryExerciseEquipmentPet.
  ///
  /// In tr, this message translates to:
  /// **'Egzersiz Ekipmanları'**
  String get subSubcategoryExerciseEquipmentPet;

  /// No description provided for @subSubcategoryDryFood.
  ///
  /// In tr, this message translates to:
  /// **'Kuru Mama'**
  String get subSubcategoryDryFood;

  /// No description provided for @subSubcategoryWetFood.
  ///
  /// In tr, this message translates to:
  /// **'Yaş Mama'**
  String get subSubcategoryWetFood;

  /// No description provided for @subSubcategoryTreatsSnacks.
  ///
  /// In tr, this message translates to:
  /// **'Ödül ve Atıştırmalık'**
  String get subSubcategoryTreatsSnacks;

  /// No description provided for @subSubcategorySupplementsPet.
  ///
  /// In tr, this message translates to:
  /// **'Takviyeler'**
  String get subSubcategorySupplementsPet;

  /// No description provided for @subSubcategorySpecialDietFood.
  ///
  /// In tr, this message translates to:
  /// **'Özel Diyet Maması'**
  String get subSubcategorySpecialDietFood;

  /// No description provided for @subSubcategoryOrganicFood.
  ///
  /// In tr, this message translates to:
  /// **'Organik Mama'**
  String get subSubcategoryOrganicFood;

  /// No description provided for @subSubcategoryFleaTickControl.
  ///
  /// In tr, this message translates to:
  /// **'Pire ve Kene Kontrolü'**
  String get subSubcategoryFleaTickControl;

  /// No description provided for @subSubcategoryVitaminsSupplementsPet.
  ///
  /// In tr, this message translates to:
  /// **'Vitamin ve Takviyeler'**
  String get subSubcategoryVitaminsSupplementsPet;

  /// No description provided for @subSubcategoryFirstAidPet.
  ///
  /// In tr, this message translates to:
  /// **'İlk Yardım'**
  String get subSubcategoryFirstAidPet;

  /// No description provided for @subSubcategoryDentalCarePet.
  ///
  /// In tr, this message translates to:
  /// **'Diş Bakımı'**
  String get subSubcategoryDentalCarePet;

  /// No description provided for @subSubcategorySkinCoatCare.
  ///
  /// In tr, this message translates to:
  /// **'Deri ve Tüy Bakımı'**
  String get subSubcategorySkinCoatCare;

  /// No description provided for @subSubcategoryHealthMonitoringPet.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık Takibi'**
  String get subSubcategoryHealthMonitoringPet;

  /// No description provided for @subSubcategoryPetCarriers.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Taşıma Çantaları'**
  String get subSubcategoryPetCarriers;

  /// No description provided for @subSubcategoryPetStrollers.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Arabaları'**
  String get subSubcategoryPetStrollers;

  /// No description provided for @subSubcategoryPetGates.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Bariyerleri'**
  String get subSubcategoryPetGates;

  /// No description provided for @subSubcategoryTravelAccessoriesPet.
  ///
  /// In tr, this message translates to:
  /// **'Seyahat Aksesuarları'**
  String get subSubcategoryTravelAccessoriesPet;

  /// No description provided for @subSubcategoryPetIDTags.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Kimlik Etiketleri'**
  String get subSubcategoryPetIDTags;

  /// No description provided for @subSubcategoryCleanupSupplies.
  ///
  /// In tr, this message translates to:
  /// **'Temizlik Malzemeleri'**
  String get subSubcategoryCleanupSupplies;

  /// No description provided for @subSubcategoryTrainingTreats.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Ödülleri'**
  String get subSubcategoryTrainingTreats;

  /// No description provided for @subSubcategoryTrainingTools.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Araçları'**
  String get subSubcategoryTrainingTools;

  /// No description provided for @subSubcategoryClickers.
  ///
  /// In tr, this message translates to:
  /// **'Kliker'**
  String get subSubcategoryClickers;

  /// No description provided for @subSubcategoryTrainingPads.
  ///
  /// In tr, this message translates to:
  /// **'Eğitim Pedleri'**
  String get subSubcategoryTrainingPads;

  /// No description provided for @subSubcategoryBehavioralAids.
  ///
  /// In tr, this message translates to:
  /// **'Davranış Yardımcıları'**
  String get subSubcategoryBehavioralAids;

  /// No description provided for @subSubcategoryEngineParts.
  ///
  /// In tr, this message translates to:
  /// **'Motor Parçaları'**
  String get subSubcategoryEngineParts;

  /// No description provided for @subSubcategoryBrakeParts.
  ///
  /// In tr, this message translates to:
  /// **'Fren Parçaları'**
  String get subSubcategoryBrakeParts;

  /// No description provided for @subSubcategorySuspensionParts.
  ///
  /// In tr, this message translates to:
  /// **'Süspansiyon Parçaları'**
  String get subSubcategorySuspensionParts;

  /// No description provided for @subSubcategoryExhaustParts.
  ///
  /// In tr, this message translates to:
  /// **'Egzoz Parçaları'**
  String get subSubcategoryExhaustParts;

  /// No description provided for @subSubcategoryElectricalPartsAuto.
  ///
  /// In tr, this message translates to:
  /// **'Elektrik Parçaları'**
  String get subSubcategoryElectricalPartsAuto;

  /// No description provided for @subSubcategoryBodyParts.
  ///
  /// In tr, this message translates to:
  /// **'Kaporta Parçaları'**
  String get subSubcategoryBodyParts;

  /// No description provided for @subSubcategoryInteriorAccessoriesAuto.
  ///
  /// In tr, this message translates to:
  /// **'İç Aksesuar'**
  String get subSubcategoryInteriorAccessoriesAuto;

  /// No description provided for @subSubcategoryExteriorAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Dış Aksesuar'**
  String get subSubcategoryExteriorAccessories;

  /// No description provided for @subSubcategoryCarWashProducts.
  ///
  /// In tr, this message translates to:
  /// **'Araba Yıkama Ürünleri'**
  String get subSubcategoryCarWashProducts;

  /// No description provided for @subSubcategoryWaxPolish.
  ///
  /// In tr, this message translates to:
  /// **'Cila ve Parlatıcı'**
  String get subSubcategoryWaxPolish;

  /// No description provided for @subSubcategoryInteriorCleaners.
  ///
  /// In tr, this message translates to:
  /// **'İç Temizleyiciler'**
  String get subSubcategoryInteriorCleaners;

  /// No description provided for @subSubcategoryEngineCleaners.
  ///
  /// In tr, this message translates to:
  /// **'Motor Temizleyicileri'**
  String get subSubcategoryEngineCleaners;

  /// No description provided for @subSubcategoryTireCare.
  ///
  /// In tr, this message translates to:
  /// **'Lastik Bakımı'**
  String get subSubcategoryTireCare;

  /// No description provided for @subSubcategoryGlassCleaners.
  ///
  /// In tr, this message translates to:
  /// **'Cam Temizleyicileri'**
  String get subSubcategoryGlassCleaners;

  /// No description provided for @subSubcategorySummerTires.
  ///
  /// In tr, this message translates to:
  /// **'Yaz Lastikleri'**
  String get subSubcategorySummerTires;

  /// No description provided for @subSubcategoryWinterTires.
  ///
  /// In tr, this message translates to:
  /// **'Kış Lastikleri'**
  String get subSubcategoryWinterTires;

  /// No description provided for @subSubcategoryAllSeasonTires.
  ///
  /// In tr, this message translates to:
  /// **'Dört Mevsim Lastikleri'**
  String get subSubcategoryAllSeasonTires;

  /// No description provided for @subSubcategoryPerformanceTires.
  ///
  /// In tr, this message translates to:
  /// **'Performans Lastikleri'**
  String get subSubcategoryPerformanceTires;

  /// No description provided for @subSubcategoryAlloyWheels.
  ///
  /// In tr, this message translates to:
  /// **'Alaşım Jantlar'**
  String get subSubcategoryAlloyWheels;

  /// No description provided for @subSubcategorySteelWheels.
  ///
  /// In tr, this message translates to:
  /// **'Çelik Jantlar'**
  String get subSubcategorySteelWheels;

  /// No description provided for @subSubcategoryWheelAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Jant Aksesuarları'**
  String get subSubcategoryWheelAccessories;

  /// No description provided for @subSubcategoryCarStereos.
  ///
  /// In tr, this message translates to:
  /// **'Araba Teyipleri'**
  String get subSubcategoryCarStereos;

  /// No description provided for @subSubcategoryGPSNavigation.
  ///
  /// In tr, this message translates to:
  /// **'GPS Navigasyon'**
  String get subSubcategoryGPSNavigation;

  /// No description provided for @subSubcategoryDashCameras.
  ///
  /// In tr, this message translates to:
  /// **'Araç Kameraları'**
  String get subSubcategoryDashCameras;

  /// No description provided for @subSubcategoryCarAlarms.
  ///
  /// In tr, this message translates to:
  /// **'Araba Alarmları'**
  String get subSubcategoryCarAlarms;

  /// No description provided for @subSubcategoryCarSpeakers.
  ///
  /// In tr, this message translates to:
  /// **'Araba Hoparlörleri'**
  String get subSubcategoryCarSpeakers;

  /// No description provided for @subSubcategoryCarAmplifiers.
  ///
  /// In tr, this message translates to:
  /// **'Araba Amfileri'**
  String get subSubcategoryCarAmplifiers;

  /// No description provided for @subSubcategoryMotorcycleEngines.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Motorları'**
  String get subSubcategoryMotorcycleEngines;

  /// No description provided for @subSubcategoryMotorcycleBrakes.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Frenleri'**
  String get subSubcategoryMotorcycleBrakes;

  /// No description provided for @subSubcategoryMotorcycleTires.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Lastikleri'**
  String get subSubcategoryMotorcycleTires;

  /// No description provided for @subSubcategoryMotorcycleLights.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Işıkları'**
  String get subSubcategoryMotorcycleLights;

  /// No description provided for @subSubcategoryMotorcycleExhaust.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Egzozu'**
  String get subSubcategoryMotorcycleExhaust;

  /// No description provided for @subSubcategoryMotorcycleBodyParts.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Kaporta Parçaları'**
  String get subSubcategoryMotorcycleBodyParts;

  /// No description provided for @subSubcategoryMotorcycleHelmets.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Kaskları'**
  String get subSubcategoryMotorcycleHelmets;

  /// No description provided for @subSubcategoryMotorcycleGloves.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Eldivenleri'**
  String get subSubcategoryMotorcycleGloves;

  /// No description provided for @subSubcategoryMotorcycleJackets.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Ceketleri'**
  String get subSubcategoryMotorcycleJackets;

  /// No description provided for @subSubcategoryMotorcycleBoots.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Botları'**
  String get subSubcategoryMotorcycleBoots;

  /// No description provided for @subSubcategoryMotorcycleBags.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Çantaları'**
  String get subSubcategoryMotorcycleBags;

  /// No description provided for @subSubcategoryMotorcycleTools.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Aletleri'**
  String get subSubcategoryMotorcycleTools;

  /// No description provided for @subSubcategoryHandToolsAuto.
  ///
  /// In tr, this message translates to:
  /// **'El Aletleri'**
  String get subSubcategoryHandToolsAuto;

  /// No description provided for @subSubcategoryPowerToolsAuto.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Aletler'**
  String get subSubcategoryPowerToolsAuto;

  /// No description provided for @subSubcategoryDiagnosticTools.
  ///
  /// In tr, this message translates to:
  /// **'Teşhis Aletleri'**
  String get subSubcategoryDiagnosticTools;

  /// No description provided for @subSubcategoryLiftingEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Kaldırma Ekipmanları'**
  String get subSubcategoryLiftingEquipment;

  /// No description provided for @subSubcategoryMeasuringToolsAuto.
  ///
  /// In tr, this message translates to:
  /// **'Ölçüm Aletleri'**
  String get subSubcategoryMeasuringToolsAuto;

  /// No description provided for @subSubcategoryEngineOil.
  ///
  /// In tr, this message translates to:
  /// **'Motor Yağı'**
  String get subSubcategoryEngineOil;

  /// No description provided for @subSubcategoryTransmissionFluid.
  ///
  /// In tr, this message translates to:
  /// **'Şanzıman Yağı'**
  String get subSubcategoryTransmissionFluid;

  /// No description provided for @subSubcategoryBrakeFluid.
  ///
  /// In tr, this message translates to:
  /// **'Fren Hidroliği'**
  String get subSubcategoryBrakeFluid;

  /// No description provided for @subSubcategoryCoolant.
  ///
  /// In tr, this message translates to:
  /// **'Antifriz'**
  String get subSubcategoryCoolant;

  /// No description provided for @subSubcategoryPowerSteeringFluid.
  ///
  /// In tr, this message translates to:
  /// **'Direksiyon Hidroliği'**
  String get subSubcategoryPowerSteeringFluid;

  /// No description provided for @subSubcategoryWindshieldWasherFluid.
  ///
  /// In tr, this message translates to:
  /// **'Cam Suyu'**
  String get subSubcategoryWindshieldWasherFluid;

  /// No description provided for @subSubcategoryMultivitamins.
  ///
  /// In tr, this message translates to:
  /// **'Multivitaminler'**
  String get subSubcategoryMultivitamins;

  /// No description provided for @subSubcategoryVitaminC.
  ///
  /// In tr, this message translates to:
  /// **'C Vitamini'**
  String get subSubcategoryVitaminC;

  /// No description provided for @subSubcategoryVitaminD.
  ///
  /// In tr, this message translates to:
  /// **'D Vitamini'**
  String get subSubcategoryVitaminD;

  /// No description provided for @subSubcategoryCalcium.
  ///
  /// In tr, this message translates to:
  /// **'Kalsiyum'**
  String get subSubcategoryCalcium;

  /// No description provided for @subSubcategoryIron.
  ///
  /// In tr, this message translates to:
  /// **'Demir'**
  String get subSubcategoryIron;

  /// No description provided for @subSubcategoryOmega3.
  ///
  /// In tr, this message translates to:
  /// **'Omega-3'**
  String get subSubcategoryOmega3;

  /// No description provided for @subSubcategoryProteinSupplements.
  ///
  /// In tr, this message translates to:
  /// **'Protein Takviyeleri'**
  String get subSubcategoryProteinSupplements;

  /// No description provided for @subSubcategoryProbiotics.
  ///
  /// In tr, this message translates to:
  /// **'Probiyotikler'**
  String get subSubcategoryProbiotics;

  /// No description provided for @subSubcategoryBloodPressureMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Tansiyon Aletleri'**
  String get subSubcategoryBloodPressureMonitors;

  /// No description provided for @subSubcategoryThermometers.
  ///
  /// In tr, this message translates to:
  /// **'Termometreler'**
  String get subSubcategoryThermometers;

  /// No description provided for @subSubcategoryGlucoseMeters.
  ///
  /// In tr, this message translates to:
  /// **'Şeker Ölçüm Cihazları'**
  String get subSubcategoryGlucoseMeters;

  /// No description provided for @subSubcategoryPulseOximeters.
  ///
  /// In tr, this message translates to:
  /// **'Nabız Oksimetreleri'**
  String get subSubcategoryPulseOximeters;

  /// No description provided for @subSubcategoryNebulizers.
  ///
  /// In tr, this message translates to:
  /// **'Nebülizörler'**
  String get subSubcategoryNebulizers;

  /// No description provided for @subSubcategoryStethoscopes.
  ///
  /// In tr, this message translates to:
  /// **'Stetoskoplar'**
  String get subSubcategoryStethoscopes;

  /// No description provided for @subSubcategoryBandages.
  ///
  /// In tr, this message translates to:
  /// **'Bandajlar'**
  String get subSubcategoryBandages;

  /// No description provided for @subSubcategoryAntiseptics.
  ///
  /// In tr, this message translates to:
  /// **'Antiseptikler'**
  String get subSubcategoryAntiseptics;

  /// No description provided for @subSubcategoryPainRelief.
  ///
  /// In tr, this message translates to:
  /// **'Ağrı Kesiciler'**
  String get subSubcategoryPainRelief;

  /// No description provided for @subSubcategoryWoundCare.
  ///
  /// In tr, this message translates to:
  /// **'Yara Bakımı'**
  String get subSubcategoryWoundCare;

  /// No description provided for @subSubcategoryFirstAidKits.
  ///
  /// In tr, this message translates to:
  /// **'İlk Yardım Setleri'**
  String get subSubcategoryFirstAidKits;

  /// No description provided for @subSubcategoryEmergencySupplies.
  ///
  /// In tr, this message translates to:
  /// **'Acil Durum Malzemeleri'**
  String get subSubcategoryEmergencySupplies;

  /// No description provided for @subSubcategoryWeightManagement.
  ///
  /// In tr, this message translates to:
  /// **'Kilo Kontrolü'**
  String get subSubcategoryWeightManagement;

  /// No description provided for @subSubcategoryDigestiveHealth.
  ///
  /// In tr, this message translates to:
  /// **'Sindirim Sağlığı'**
  String get subSubcategoryDigestiveHealth;

  /// No description provided for @subSubcategoryHeartHealth.
  ///
  /// In tr, this message translates to:
  /// **'Kalp Sağlığı'**
  String get subSubcategoryHeartHealth;

  /// No description provided for @subSubcategoryJointHealth.
  ///
  /// In tr, this message translates to:
  /// **'Eklem Sağlığı'**
  String get subSubcategoryJointHealth;

  /// No description provided for @subSubcategoryMentalHealth.
  ///
  /// In tr, this message translates to:
  /// **'Ruh Sağlığı'**
  String get subSubcategoryMentalHealth;

  /// No description provided for @subSubcategorySleepAids.
  ///
  /// In tr, this message translates to:
  /// **'Uyku Yardımcıları'**
  String get subSubcategorySleepAids;

  /// No description provided for @subSubcategoryEnergyBoosters.
  ///
  /// In tr, this message translates to:
  /// **'Enerji Artırıcılar'**
  String get subSubcategoryEnergyBoosters;

  /// No description provided for @subSubcategoryWheelchairs.
  ///
  /// In tr, this message translates to:
  /// **'Tekerlekli Sandalyeler'**
  String get subSubcategoryWheelchairs;

  /// No description provided for @subSubcategoryWalkers.
  ///
  /// In tr, this message translates to:
  /// **'Yürütecler'**
  String get subSubcategoryWalkers;

  /// No description provided for @subSubcategoryCrutches.
  ///
  /// In tr, this message translates to:
  /// **'Koltuk Değnekleri'**
  String get subSubcategoryCrutches;

  /// No description provided for @subSubcategoryCanes.
  ///
  /// In tr, this message translates to:
  /// **'Bastonlar'**
  String get subSubcategoryCanes;

  /// No description provided for @subSubcategoryMobilityScooters.
  ///
  /// In tr, this message translates to:
  /// **'Mobilite Scooter\'ları'**
  String get subSubcategoryMobilityScooters;

  /// No description provided for @subSubcategoryBathSafety.
  ///
  /// In tr, this message translates to:
  /// **'Banyo Güvenliği'**
  String get subSubcategoryBathSafety;

  /// No description provided for @subSubcategoryHerbalRemedies.
  ///
  /// In tr, this message translates to:
  /// **'Bitkisel İlaçlar'**
  String get subSubcategoryHerbalRemedies;

  /// No description provided for @subSubcategoryAromatherapy.
  ///
  /// In tr, this message translates to:
  /// **'Aromaterapi'**
  String get subSubcategoryAromatherapy;

  /// No description provided for @subSubcategoryHomeopathy.
  ///
  /// In tr, this message translates to:
  /// **'Homeopati'**
  String get subSubcategoryHomeopathy;

  /// No description provided for @subSubcategoryTraditionalMedicine.
  ///
  /// In tr, this message translates to:
  /// **'Geleneksel Tıp'**
  String get subSubcategoryTraditionalMedicine;

  /// No description provided for @subSubcategoryNaturalSupplements.
  ///
  /// In tr, this message translates to:
  /// **'Doğal Takviyeler'**
  String get subSubcategoryNaturalSupplements;

  /// No description provided for @subSubcategoryProteinPowders.
  ///
  /// In tr, this message translates to:
  /// **'Protein Tozları'**
  String get subSubcategoryProteinPowders;

  /// No description provided for @subSubcategoryPreWorkout.
  ///
  /// In tr, this message translates to:
  /// **'Antrenman Öncesi'**
  String get subSubcategoryPreWorkout;

  /// No description provided for @subSubcategoryPostWorkout.
  ///
  /// In tr, this message translates to:
  /// **'Antrenman Sonrası'**
  String get subSubcategoryPostWorkout;

  /// No description provided for @subSubcategoryFatBurners.
  ///
  /// In tr, this message translates to:
  /// **'Yağ Yakıcılar'**
  String get subSubcategoryFatBurners;

  /// No description provided for @subSubcategoryMealReplacements.
  ///
  /// In tr, this message translates to:
  /// **'Öğün Yerine Geçen Ürünler'**
  String get subSubcategoryMealReplacements;

  /// No description provided for @subSubcategoryHealthySnacks.
  ///
  /// In tr, this message translates to:
  /// **'Sağlıklı Atıştırmalıklar'**
  String get subSubcategoryHealthySnacks;

  /// No description provided for @subSubcategoryContraceptives.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Kontrol Yöntemleri'**
  String get subSubcategoryContraceptives;

  /// No description provided for @subSubcategoryPregnancyTests.
  ///
  /// In tr, this message translates to:
  /// **'Hamilelik Testleri'**
  String get subSubcategoryPregnancyTests;

  /// No description provided for @subSubcategoryFertilityProducts.
  ///
  /// In tr, this message translates to:
  /// **'Doğurganlık Ürünleri'**
  String get subSubcategoryFertilityProducts;

  /// No description provided for @subSubcategoryPersonalLubricants.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Kayganlaştırıcılar'**
  String get subSubcategoryPersonalLubricants;

  /// No description provided for @subSubcategoryEnhancementProducts.
  ///
  /// In tr, this message translates to:
  /// **'Güçlendirici Ürünler'**
  String get subSubcategoryEnhancementProducts;

  /// No description provided for @categoryFlowersGifts.
  ///
  /// In tr, this message translates to:
  /// **'Çiçek & Hediye'**
  String get categoryFlowersGifts;

  /// No description provided for @subcategoryBouquetsArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Buket & Aranjmanlar'**
  String get subcategoryBouquetsArrangements;

  /// No description provided for @subcategoryPottedPlants.
  ///
  /// In tr, this message translates to:
  /// **'Saksı Çiçekleri'**
  String get subcategoryPottedPlants;

  /// No description provided for @subcategoryGiftArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Hediye Aranjmanları'**
  String get subcategoryGiftArrangements;

  /// No description provided for @subcategoryFlowerAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Çiçek Aksesuarları'**
  String get subcategoryFlowerAccessories;

  /// No description provided for @subcategoryWreathsCenterpieces.
  ///
  /// In tr, this message translates to:
  /// **'Çelenkler & Masa Süsleri'**
  String get subcategoryWreathsCenterpieces;

  /// No description provided for @subSubcategoryBouquets.
  ///
  /// In tr, this message translates to:
  /// **'Buketler'**
  String get subSubcategoryBouquets;

  /// No description provided for @subSubcategoryFlowerArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Çiçek Aranjmanları'**
  String get subSubcategoryFlowerArrangements;

  /// No description provided for @subSubcategoryMixedArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Karışık Aranjmanlar'**
  String get subSubcategoryMixedArrangements;

  /// No description provided for @subSubcategorySingleFlowerTypes.
  ///
  /// In tr, this message translates to:
  /// **'Tek Tip Çiçekler'**
  String get subSubcategorySingleFlowerTypes;

  /// No description provided for @subSubcategorySeasonalArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Mevsimsel Aranjmanlar'**
  String get subSubcategorySeasonalArrangements;

  /// No description provided for @subSubcategoryIndoorPlants.
  ///
  /// In tr, this message translates to:
  /// **'İç Mekan Bitkileri'**
  String get subSubcategoryIndoorPlants;

  /// No description provided for @subSubcategoryOutdoorPlants.
  ///
  /// In tr, this message translates to:
  /// **'Dış Mekan Bitkileri'**
  String get subSubcategoryOutdoorPlants;

  /// No description provided for @subSubcategorySucculents.
  ///
  /// In tr, this message translates to:
  /// **'Sukulentler'**
  String get subSubcategorySucculents;

  /// No description provided for @subSubcategoryOrchids.
  ///
  /// In tr, this message translates to:
  /// **'Orkideler'**
  String get subSubcategoryOrchids;

  /// No description provided for @subSubcategoryBonsai.
  ///
  /// In tr, this message translates to:
  /// **'Bonsai'**
  String get subSubcategoryBonsai;

  /// No description provided for @subSubcategoryCacti.
  ///
  /// In tr, this message translates to:
  /// **'Kaktüsler'**
  String get subSubcategoryCacti;

  /// No description provided for @subSubcategoryChocolateArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Çikolatalı Aranjmanlar'**
  String get subSubcategoryChocolateArrangements;

  /// No description provided for @subSubcategoryEdibleArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Yenilebilir Aranjmanlar'**
  String get subSubcategoryEdibleArrangements;

  /// No description provided for @subSubcategoryFruitBaskets.
  ///
  /// In tr, this message translates to:
  /// **'Meyve Sepetleri'**
  String get subSubcategoryFruitBaskets;

  /// No description provided for @subSubcategoryGiftCombos.
  ///
  /// In tr, this message translates to:
  /// **'Hediye Kombinleri'**
  String get subSubcategoryGiftCombos;

  /// No description provided for @subSubcategoryBalloonArrangements.
  ///
  /// In tr, this message translates to:
  /// **'Balon Aranjmanları'**
  String get subSubcategoryBalloonArrangements;

  /// No description provided for @subSubcategoryPlantersPots.
  ///
  /// In tr, this message translates to:
  /// **'Saksılar'**
  String get subSubcategoryPlantersPots;

  /// No description provided for @subSubcategoryFloralFoam.
  ///
  /// In tr, this message translates to:
  /// **'Çiçek Süngeri'**
  String get subSubcategoryFloralFoam;

  /// No description provided for @subSubcategoryRibbonsWraps.
  ///
  /// In tr, this message translates to:
  /// **'Kurdele & Ambalaj'**
  String get subSubcategoryRibbonsWraps;

  /// No description provided for @subSubcategoryPlantCareProducts.
  ///
  /// In tr, this message translates to:
  /// **'Bitki Bakım Ürünleri'**
  String get subSubcategoryPlantCareProducts;

  /// No description provided for @subSubcategoryDecorativeAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Dekoratif Aksesuarlar'**
  String get subSubcategoryDecorativeAccessories;

  /// No description provided for @subSubcategoryFuneralWreaths.
  ///
  /// In tr, this message translates to:
  /// **'Cenaze Çelenkleri'**
  String get subSubcategoryFuneralWreaths;

  /// No description provided for @subSubcategoryDecorativeWreaths.
  ///
  /// In tr, this message translates to:
  /// **'Dekoratif Çelenkler'**
  String get subSubcategoryDecorativeWreaths;

  /// No description provided for @subSubcategoryTableCenterpieces.
  ///
  /// In tr, this message translates to:
  /// **'Masa Merkez Parçaları'**
  String get subSubcategoryTableCenterpieces;

  /// No description provided for @subSubcategoryEventDecorations.
  ///
  /// In tr, this message translates to:
  /// **'Etkinlik Süslemeleri'**
  String get subSubcategoryEventDecorations;

  /// No description provided for @subSubcategorySeasonalWreaths.
  ///
  /// In tr, this message translates to:
  /// **'Mevsimsel Çelenkler'**
  String get subSubcategorySeasonalWreaths;

  /// No description provided for @whiteGoodRefrigerator.
  ///
  /// In tr, this message translates to:
  /// **'Buzdolabı'**
  String get whiteGoodRefrigerator;

  /// No description provided for @whiteGoodWashingMachine.
  ///
  /// In tr, this message translates to:
  /// **'Çamaşır Makinesi'**
  String get whiteGoodWashingMachine;

  /// No description provided for @whiteGoodDishwasher.
  ///
  /// In tr, this message translates to:
  /// **'Bulaşık Makinesi'**
  String get whiteGoodDishwasher;

  /// No description provided for @whiteGoodDryer.
  ///
  /// In tr, this message translates to:
  /// **'Kurutma Makinesi'**
  String get whiteGoodDryer;

  /// No description provided for @whiteGoodFreezer.
  ///
  /// In tr, this message translates to:
  /// **'Derin Dondurucu'**
  String get whiteGoodFreezer;

  /// No description provided for @pleaseSelectWhiteGood.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir beyaz eşya seçin'**
  String get pleaseSelectWhiteGood;

  /// No description provided for @selectWhiteGood.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz Eşya Seç'**
  String get selectWhiteGood;

  /// No description provided for @selectWhiteGoodType.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz eşya türünü seçin'**
  String get selectWhiteGoodType;

  /// No description provided for @computerComponentCPU.
  ///
  /// In tr, this message translates to:
  /// **'İşlemci (CPU)'**
  String get computerComponentCPU;

  /// No description provided for @computerComponentGPU.
  ///
  /// In tr, this message translates to:
  /// **'Ekran Kartı (GPU)'**
  String get computerComponentGPU;

  /// No description provided for @computerComponentRAM.
  ///
  /// In tr, this message translates to:
  /// **'Bellek (RAM)'**
  String get computerComponentRAM;

  /// No description provided for @computerComponentMotherboard.
  ///
  /// In tr, this message translates to:
  /// **'Anakart'**
  String get computerComponentMotherboard;

  /// No description provided for @computerComponentSSD.
  ///
  /// In tr, this message translates to:
  /// **'SSD Disk'**
  String get computerComponentSSD;

  /// No description provided for @computerComponentHDD.
  ///
  /// In tr, this message translates to:
  /// **'Sabit Disk (HDD)'**
  String get computerComponentHDD;

  /// No description provided for @computerComponentPowerSupply.
  ///
  /// In tr, this message translates to:
  /// **'Güç Kaynağı'**
  String get computerComponentPowerSupply;

  /// No description provided for @computerComponentCoolingSystem.
  ///
  /// In tr, this message translates to:
  /// **'Soğutma Sistemi'**
  String get computerComponentCoolingSystem;

  /// No description provided for @computerComponentCase.
  ///
  /// In tr, this message translates to:
  /// **'Bilgisayar Kasası'**
  String get computerComponentCase;

  /// No description provided for @computerComponentOpticalDrive.
  ///
  /// In tr, this message translates to:
  /// **'CD/DVD Sürücü'**
  String get computerComponentOpticalDrive;

  /// No description provided for @computerComponentNetworkCard.
  ///
  /// In tr, this message translates to:
  /// **'Ağ Kartı'**
  String get computerComponentNetworkCard;

  /// No description provided for @computerComponentSoundCard.
  ///
  /// In tr, this message translates to:
  /// **'Ses Kartı'**
  String get computerComponentSoundCard;

  /// No description provided for @computerComponentMonitor.
  ///
  /// In tr, this message translates to:
  /// **'Monitör'**
  String get computerComponentMonitor;

  /// No description provided for @computerComponentKeyboard.
  ///
  /// In tr, this message translates to:
  /// **'Klavye'**
  String get computerComponentKeyboard;

  /// No description provided for @computerComponentMouse.
  ///
  /// In tr, this message translates to:
  /// **'Fare'**
  String get computerComponentMouse;

  /// No description provided for @computerComponentSpeakers.
  ///
  /// In tr, this message translates to:
  /// **'Hoparlör'**
  String get computerComponentSpeakers;

  /// No description provided for @computerComponentWebcam.
  ///
  /// In tr, this message translates to:
  /// **'Web Kamerası'**
  String get computerComponentWebcam;

  /// No description provided for @computerComponentHeadset.
  ///
  /// In tr, this message translates to:
  /// **'Kulaklık'**
  String get computerComponentHeadset;

  /// No description provided for @pleaseSelectComputerComponent.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir bilgisayar bileşeni seçin'**
  String get pleaseSelectComputerComponent;

  /// No description provided for @selectComputerComponent.
  ///
  /// In tr, this message translates to:
  /// **'Bilgisayar Bileşeni Seç'**
  String get selectComputerComponent;

  /// No description provided for @selectComputerComponentType.
  ///
  /// In tr, this message translates to:
  /// **'Bilgisayar bileşeni türünü seçin'**
  String get selectComputerComponentType;

  /// No description provided for @consoleBrandPlayStation.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation'**
  String get consoleBrandPlayStation;

  /// No description provided for @consoleBrandXbox.
  ///
  /// In tr, this message translates to:
  /// **'Xbox'**
  String get consoleBrandXbox;

  /// No description provided for @consoleBrandNintendo.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo'**
  String get consoleBrandNintendo;

  /// No description provided for @consoleBrandPC.
  ///
  /// In tr, this message translates to:
  /// **'PC Oyun'**
  String get consoleBrandPC;

  /// No description provided for @consoleBrandMobile.
  ///
  /// In tr, this message translates to:
  /// **'Mobil Oyun'**
  String get consoleBrandMobile;

  /// No description provided for @consoleBrandRetro.
  ///
  /// In tr, this message translates to:
  /// **'Retro Oyun'**
  String get consoleBrandRetro;

  /// No description provided for @consoleVariantPS5.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 5'**
  String get consoleVariantPS5;

  /// No description provided for @consoleVariantPS5Digital.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 5 Digital Edition'**
  String get consoleVariantPS5Digital;

  /// No description provided for @consoleVariantPS5Slim.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 5 Slim'**
  String get consoleVariantPS5Slim;

  /// No description provided for @consoleVariantPS5Pro.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 5 Pro'**
  String get consoleVariantPS5Pro;

  /// No description provided for @consoleVariantPS4.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 4'**
  String get consoleVariantPS4;

  /// No description provided for @consoleVariantPS4Slim.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 4 Slim'**
  String get consoleVariantPS4Slim;

  /// No description provided for @consoleVariantPS4Pro.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 4 Pro'**
  String get consoleVariantPS4Pro;

  /// No description provided for @consoleVariantPS3.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 3'**
  String get consoleVariantPS3;

  /// No description provided for @consoleVariantPS2.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 2'**
  String get consoleVariantPS2;

  /// No description provided for @consoleVariantPS1.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation 1'**
  String get consoleVariantPS1;

  /// No description provided for @consoleVariantPSP.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation Portable (PSP)'**
  String get consoleVariantPSP;

  /// No description provided for @consoleVariantPSVita.
  ///
  /// In tr, this message translates to:
  /// **'PlayStation Vita'**
  String get consoleVariantPSVita;

  /// No description provided for @consoleVariantXboxSeriesX.
  ///
  /// In tr, this message translates to:
  /// **'Xbox Series X'**
  String get consoleVariantXboxSeriesX;

  /// No description provided for @consoleVariantXboxSeriesS.
  ///
  /// In tr, this message translates to:
  /// **'Xbox Series S'**
  String get consoleVariantXboxSeriesS;

  /// No description provided for @consoleVariantXboxOneX.
  ///
  /// In tr, this message translates to:
  /// **'Xbox One X'**
  String get consoleVariantXboxOneX;

  /// No description provided for @consoleVariantXboxOneS.
  ///
  /// In tr, this message translates to:
  /// **'Xbox One S'**
  String get consoleVariantXboxOneS;

  /// No description provided for @consoleVariantXboxOne.
  ///
  /// In tr, this message translates to:
  /// **'Xbox One'**
  String get consoleVariantXboxOne;

  /// No description provided for @consoleVariantXbox360.
  ///
  /// In tr, this message translates to:
  /// **'Xbox 360'**
  String get consoleVariantXbox360;

  /// No description provided for @consoleVariantXboxOriginal.
  ///
  /// In tr, this message translates to:
  /// **'Xbox Original'**
  String get consoleVariantXboxOriginal;

  /// No description provided for @consoleVariantSwitchOLED.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Switch OLED'**
  String get consoleVariantSwitchOLED;

  /// No description provided for @consoleVariantSwitchStandard.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Switch'**
  String get consoleVariantSwitchStandard;

  /// No description provided for @consoleVariantSwitchLite.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Switch Lite'**
  String get consoleVariantSwitchLite;

  /// No description provided for @consoleVariantWiiU.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Wii U'**
  String get consoleVariantWiiU;

  /// No description provided for @consoleVariantWii.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Wii'**
  String get consoleVariantWii;

  /// No description provided for @consoleVariantGameCube.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo GameCube'**
  String get consoleVariantGameCube;

  /// No description provided for @consoleVariantN64.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo 64'**
  String get consoleVariantN64;

  /// No description provided for @consoleVariantSNES.
  ///
  /// In tr, this message translates to:
  /// **'Super Nintendo (SNES)'**
  String get consoleVariantSNES;

  /// No description provided for @consoleVariantNES.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo Entertainment System (NES)'**
  String get consoleVariantNES;

  /// No description provided for @consoleVariant3DSXL.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo 3DS XL'**
  String get consoleVariant3DSXL;

  /// No description provided for @consoleVariant3DS.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo 3DS'**
  String get consoleVariant3DS;

  /// No description provided for @consoleVariant2DS.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo 2DS'**
  String get consoleVariant2DS;

  /// No description provided for @consoleVariantDSLite.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo DS Lite'**
  String get consoleVariantDSLite;

  /// No description provided for @consoleVariantDS.
  ///
  /// In tr, this message translates to:
  /// **'Nintendo DS'**
  String get consoleVariantDS;

  /// No description provided for @consoleVariantGameBoyAdvance.
  ///
  /// In tr, this message translates to:
  /// **'Game Boy Advance'**
  String get consoleVariantGameBoyAdvance;

  /// No description provided for @consoleVariantGameBoyColor.
  ///
  /// In tr, this message translates to:
  /// **'Game Boy Color'**
  String get consoleVariantGameBoyColor;

  /// No description provided for @consoleVariantGameBoy.
  ///
  /// In tr, this message translates to:
  /// **'Game Boy'**
  String get consoleVariantGameBoy;

  /// No description provided for @consoleVariantSteamDeck.
  ///
  /// In tr, this message translates to:
  /// **'Steam Deck'**
  String get consoleVariantSteamDeck;

  /// No description provided for @consoleVariantGamingPC.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Bilgisayarı'**
  String get consoleVariantGamingPC;

  /// No description provided for @consoleVariantGamingLaptop.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Dizüstü'**
  String get consoleVariantGamingLaptop;

  /// No description provided for @consoleVariantMiniPC.
  ///
  /// In tr, this message translates to:
  /// **'Mini PC'**
  String get consoleVariantMiniPC;

  /// No description provided for @consoleVariantiOS.
  ///
  /// In tr, this message translates to:
  /// **'iOS (iPhone/iPad)'**
  String get consoleVariantiOS;

  /// No description provided for @consoleVariantAndroid.
  ///
  /// In tr, this message translates to:
  /// **'Android'**
  String get consoleVariantAndroid;

  /// No description provided for @consoleVariantAtari2600.
  ///
  /// In tr, this message translates to:
  /// **'Atari 2600'**
  String get consoleVariantAtari2600;

  /// No description provided for @consoleVariantSegaGenesis.
  ///
  /// In tr, this message translates to:
  /// **'Sega Genesis'**
  String get consoleVariantSegaGenesis;

  /// No description provided for @consoleVariantSegaDreamcast.
  ///
  /// In tr, this message translates to:
  /// **'Sega Dreamcast'**
  String get consoleVariantSegaDreamcast;

  /// No description provided for @consoleVariantNeoGeo.
  ///
  /// In tr, this message translates to:
  /// **'Neo Geo'**
  String get consoleVariantNeoGeo;

  /// No description provided for @consoleVariantArcadeCabinet.
  ///
  /// In tr, this message translates to:
  /// **'Atari Makinesi'**
  String get consoleVariantArcadeCabinet;

  /// No description provided for @pleaseSelectConsoleBrand.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir konsol markası seçin'**
  String get pleaseSelectConsoleBrand;

  /// No description provided for @pleaseSelectConsoleVariant.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir konsol modeli seçin'**
  String get pleaseSelectConsoleVariant;

  /// No description provided for @selectConsole.
  ///
  /// In tr, this message translates to:
  /// **'Oyun Konsolu Seç'**
  String get selectConsole;

  /// No description provided for @selectConsoleBrand.
  ///
  /// In tr, this message translates to:
  /// **'Konsol markasını'**
  String get selectConsoleBrand;

  /// No description provided for @selectConsoleVariant.
  ///
  /// In tr, this message translates to:
  /// **'Konsol modelini'**
  String get selectConsoleVariant;

  /// No description provided for @kitchenApplianceMicrowave.
  ///
  /// In tr, this message translates to:
  /// **'Mikrodalga Fırın'**
  String get kitchenApplianceMicrowave;

  /// No description provided for @kitchenApplianceCoffeeMachine.
  ///
  /// In tr, this message translates to:
  /// **'Kahve Makinesi'**
  String get kitchenApplianceCoffeeMachine;

  /// No description provided for @kitchenApplianceBlender.
  ///
  /// In tr, this message translates to:
  /// **'Blender'**
  String get kitchenApplianceBlender;

  /// No description provided for @kitchenApplianceFoodProcessor.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Robotu'**
  String get kitchenApplianceFoodProcessor;

  /// No description provided for @kitchenApplianceMixer.
  ///
  /// In tr, this message translates to:
  /// **'Mikser'**
  String get kitchenApplianceMixer;

  /// No description provided for @kitchenApplianceToaster.
  ///
  /// In tr, this message translates to:
  /// **'Ekmek Kızartma Makinesi'**
  String get kitchenApplianceToaster;

  /// No description provided for @kitchenApplianceKettle.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Su Isıtıcısı'**
  String get kitchenApplianceKettle;

  /// No description provided for @kitchenApplianceRiceCooker.
  ///
  /// In tr, this message translates to:
  /// **'Pilav Pişirme Makinesi'**
  String get kitchenApplianceRiceCooker;

  /// No description provided for @kitchenApplianceSlowCooker.
  ///
  /// In tr, this message translates to:
  /// **'Yavaş Pişirici'**
  String get kitchenApplianceSlowCooker;

  /// No description provided for @kitchenAppliancePressureCooker.
  ///
  /// In tr, this message translates to:
  /// **'Düdüklü Tencere'**
  String get kitchenAppliancePressureCooker;

  /// No description provided for @kitchenApplianceAirFryer.
  ///
  /// In tr, this message translates to:
  /// **'Hava Fritözü'**
  String get kitchenApplianceAirFryer;

  /// No description provided for @kitchenApplianceJuicer.
  ///
  /// In tr, this message translates to:
  /// **'Meyve Sıkacağı'**
  String get kitchenApplianceJuicer;

  /// No description provided for @kitchenApplianceGrinder.
  ///
  /// In tr, this message translates to:
  /// **'Kahve Değirmeni'**
  String get kitchenApplianceGrinder;

  /// No description provided for @kitchenApplianceOven.
  ///
  /// In tr, this message translates to:
  /// **'Fırın'**
  String get kitchenApplianceOven;

  /// No description provided for @kitchenApplianceRefrigerator.
  ///
  /// In tr, this message translates to:
  /// **'Buzdolabı'**
  String get kitchenApplianceRefrigerator;

  /// No description provided for @kitchenApplianceFreezer.
  ///
  /// In tr, this message translates to:
  /// **'Derin Dondurucu'**
  String get kitchenApplianceFreezer;

  /// No description provided for @kitchenApplianceDishwasher.
  ///
  /// In tr, this message translates to:
  /// **'Bulaşık Makinesi'**
  String get kitchenApplianceDishwasher;

  /// No description provided for @kitchenApplianceWashingMachine.
  ///
  /// In tr, this message translates to:
  /// **'Çamaşır Makinesi'**
  String get kitchenApplianceWashingMachine;

  /// No description provided for @kitchenApplianceDryer.
  ///
  /// In tr, this message translates to:
  /// **'Kurutma Makinesi'**
  String get kitchenApplianceDryer;

  /// No description provided for @kitchenApplianceIceMaker.
  ///
  /// In tr, this message translates to:
  /// **'Buz Makinesi'**
  String get kitchenApplianceIceMaker;

  /// No description provided for @kitchenApplianceWaterDispenser.
  ///
  /// In tr, this message translates to:
  /// **'Su Sebili'**
  String get kitchenApplianceWaterDispenser;

  /// No description provided for @kitchenApplianceFoodDehydrator.
  ///
  /// In tr, this message translates to:
  /// **'Gıda Kurutma Makinesi'**
  String get kitchenApplianceFoodDehydrator;

  /// No description provided for @kitchenApplianceSteamer.
  ///
  /// In tr, this message translates to:
  /// **'Buharda Pişirici'**
  String get kitchenApplianceSteamer;

  /// No description provided for @kitchenApplianceGrill.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Izgara'**
  String get kitchenApplianceGrill;

  /// No description provided for @kitchenApplianceSandwichMaker.
  ///
  /// In tr, this message translates to:
  /// **'Sandviç Makinesi'**
  String get kitchenApplianceSandwichMaker;

  /// No description provided for @kitchenApplianceWaffleIron.
  ///
  /// In tr, this message translates to:
  /// **'Waffle Makinesi'**
  String get kitchenApplianceWaffleIron;

  /// No description provided for @kitchenApplianceDeepFryer.
  ///
  /// In tr, this message translates to:
  /// **'Fritöz'**
  String get kitchenApplianceDeepFryer;

  /// No description provided for @kitchenApplianceBreadMaker.
  ///
  /// In tr, this message translates to:
  /// **'Ekmek Yapma Makinesi'**
  String get kitchenApplianceBreadMaker;

  /// No description provided for @kitchenApplianceYogurtMaker.
  ///
  /// In tr, this message translates to:
  /// **'Yoğurt Makinesi'**
  String get kitchenApplianceYogurtMaker;

  /// No description provided for @kitchenApplianceIceCreamMaker.
  ///
  /// In tr, this message translates to:
  /// **'Dondurma Makinesi'**
  String get kitchenApplianceIceCreamMaker;

  /// No description provided for @kitchenAppliancePastaMaker.
  ///
  /// In tr, this message translates to:
  /// **'Makarna Makinesi'**
  String get kitchenAppliancePastaMaker;

  /// No description provided for @kitchenApplianceMeatGrinder.
  ///
  /// In tr, this message translates to:
  /// **'Et Kıyma Makinesi'**
  String get kitchenApplianceMeatGrinder;

  /// No description provided for @kitchenApplianceCanOpener.
  ///
  /// In tr, this message translates to:
  /// **'Elektrikli Konserve Açacağı'**
  String get kitchenApplianceCanOpener;

  /// No description provided for @kitchenApplianceKnifeSharpener.
  ///
  /// In tr, this message translates to:
  /// **'Bıçak Bileme Makinesi'**
  String get kitchenApplianceKnifeSharpener;

  /// No description provided for @kitchenApplianceScale.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Terazisi'**
  String get kitchenApplianceScale;

  /// No description provided for @kitchenApplianceTimer.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Zamanlayıcısı'**
  String get kitchenApplianceTimer;

  /// No description provided for @pleaseSelectKitchenAppliance.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir mutfak aleti seçin'**
  String get pleaseSelectKitchenAppliance;

  /// No description provided for @selectKitchenAppliance.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak Aleti Seç'**
  String get selectKitchenAppliance;

  /// No description provided for @selectKitchenApplianceType.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak aleti türünü seçin'**
  String get selectKitchenApplianceType;

  /// No description provided for @loginTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınıza Giriş Yapın'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için e-posta ve şifrenizi girin.'**
  String get loginSubtitle;

  /// No description provided for @removeFromBasketTitle.
  ///
  /// In tr, this message translates to:
  /// **'\"{basket}\" basketinden kaldır?'**
  String removeFromBasketTitle(Object basket);

  /// No description provided for @removeFromBasketContent.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü \"{basket}\" basketinden kaldırmak istediğinizden emin misiniz?'**
  String removeFromBasketContent(Object basket);

  /// No description provided for @emailLabel.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Adresi'**
  String get emailLabel;

  /// No description provided for @emailHint.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresinizi girin'**
  String get emailHint;

  /// No description provided for @other.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get other;

  /// No description provided for @passwordLabel.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get passwordLabel;

  /// No description provided for @footwearSizeSelection.
  ///
  /// In tr, this message translates to:
  /// **'Ayakkabı Boyut Seçimi'**
  String get footwearSizeSelection;

  /// No description provided for @forgotPasswordText.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi mi unuttunuz?'**
  String get forgotPasswordText;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi Sıfırla'**
  String get forgotPasswordTitle;

  /// No description provided for @productIdCopied.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kimliği kopyalandı'**
  String get productIdCopied;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresinizi girin, size şifrenizi sıfırlamak için bir bağlantı gönderelim.'**
  String get forgotPasswordSubtitle;

  /// No description provided for @forgotPasswordSuccessSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresinize şifre sıfırlama bağlantısı gönderdik. Gelen kutunuzu kontrol edin ve talimatları takip edin.'**
  String get forgotPasswordSuccessSubtitle;

  /// No description provided for @sendResetEmailButton.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırlama E-postası Gönder'**
  String get sendResetEmailButton;

  /// No description provided for @passwordResetSent.
  ///
  /// In tr, this message translates to:
  /// **'Şifre sıfırlama e-postası gönderildi! Gelen kutunuzu kontrol edin ve şifrenizi sıfırlamak için talimatları takip edin.'**
  String get passwordResetSent;

  /// No description provided for @passwordResetSentGoogleUser.
  ///
  /// In tr, this message translates to:
  /// **'Şifre sıfırlama e-postası gönderildi! Başlangıçta Google ile kaydolduğunuz için, şifre belirlemeniz hem Google hem de e-posta/şifre ile giriş yapmanıza olanak sağlayacak.'**
  String get passwordResetSentGoogleUser;

  /// No description provided for @passwordResetResent.
  ///
  /// In tr, this message translates to:
  /// **'Şifre sıfırlama e-postası tekrar gönderildi!'**
  String get passwordResetResent;

  /// No description provided for @checkYourEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-postanızı Kontrol Edin'**
  String get checkYourEmail;

  /// No description provided for @resendEmailButton.
  ///
  /// In tr, this message translates to:
  /// **'E-postayı Tekrar Gönder'**
  String get resendEmailButton;

  /// No description provided for @rememberPasswordText.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi hatırladınız mı?'**
  String get rememberPasswordText;

  /// No description provided for @backToLoginText.
  ///
  /// In tr, this message translates to:
  /// **'Girişe Dön'**
  String get backToLoginText;

  /// No description provided for @allProductsLoaded.
  ///
  /// In tr, this message translates to:
  /// **'Tüm ürünler yüklendi'**
  String get allProductsLoaded;

  /// No description provided for @errorLoadingProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler yüklenirken hata oluştu'**
  String get errorLoadingProducts;

  /// Arama sonuç döndürmediğinde gösterilen mesaj
  ///
  /// In tr, this message translates to:
  /// **'Ürün bulunamadı.'**
  String get noProductsFound;

  /// No description provided for @collections.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonlar'**
  String get collections;

  /// No description provided for @createCollection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon Oluştur'**
  String get createCollection;

  /// No description provided for @collectionName.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon Adı'**
  String get collectionName;

  /// No description provided for @editCollection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonu Düzenle'**
  String get editCollection;

  /// No description provided for @deleteCollection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonu Sil'**
  String get deleteCollection;

  /// No description provided for @deleteCollectionConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu koleksiyonu silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'**
  String get deleteCollectionConfirmation;

  /// No description provided for @manageCollections.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonları Yönet'**
  String get manageCollections;

  /// No description provided for @collectionsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi koleksiyonlar halinde düzenleyerek müşterilerinizin daha kolay bulmasını ve vitrin oluşturmasını sağlayın.'**
  String get collectionsDescription;

  /// No description provided for @noCollectionsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz koleksiyon yok'**
  String get noCollectionsYet;

  /// No description provided for @createFirstCollection.
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için ilk koleksiyonunuzu oluşturun'**
  String get createFirstCollection;

  /// No description provided for @unnamedCollection.
  ///
  /// In tr, this message translates to:
  /// **'İsimsiz Koleksiyon'**
  String get unnamedCollection;

  /// No description provided for @addProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürün ekle'**
  String get addProducts;

  /// Ürün seçimi ekranının başlığı
  ///
  /// In tr, this message translates to:
  /// **'Ürün seçin'**
  String get selectProducts;

  /// No description provided for @done.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get done;

  /// Kaç ürün seçildiğini gösterir
  ///
  /// In tr, this message translates to:
  /// **'{count} ürün seçildi'**
  String productsSelected(int count);

  /// Mağazada ürün olmadığında gösterilen mesaj
  ///
  /// In tr, this message translates to:
  /// **'Ürün bulunmuyor'**
  String get noProductsAvailable;

  /// No description provided for @noProductsFoundDescription.
  ///
  /// In tr, this message translates to:
  /// **'Filtrelerinizi ayarlayın veya daha sonra tekrar kontrol edin'**
  String get noProductsFoundDescription;

  /// No description provided for @tryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get tryAgain;

  /// No description provided for @productsFound.
  ///
  /// In tr, this message translates to:
  /// **'ürün bulundu'**
  String get productsFound;

  /// No description provided for @noProductsMatchFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtrelerinizle eşleşen ürün bulunamadı'**
  String get noProductsMatchFilters;

  /// No description provided for @tryRemovingFilters.
  ///
  /// In tr, this message translates to:
  /// **'Bazı filtreleri kaldırmayı deneyin'**
  String get tryRemovingFilters;

  /// No description provided for @failedToDeleteSearchEntry.
  ///
  /// In tr, this message translates to:
  /// **'Arama geçmişi silinirken hata oluştu'**
  String get failedToDeleteSearchEntry;

  /// No description provided for @failedToClearHistory.
  ///
  /// In tr, this message translates to:
  /// **'Arama geçmişi temizlenirken hata oluştu'**
  String get failedToClearHistory;

  /// No description provided for @discountUpdatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'İndirim başarıyla güncellendi'**
  String get discountUpdatedSuccessfully;

  /// No description provided for @productsRemovedFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'ürün kampanyadan kaldırıldı'**
  String get productsRemovedFromCampaign;

  /// No description provided for @processing.
  ///
  /// In tr, this message translates to:
  /// **'İşleniyor...'**
  String get processing;

  /// No description provided for @adjustFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri Ayarla'**
  String get adjustFilters;

  /// No description provided for @subSubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Alt-alt Kategori'**
  String get subSubcategory;

  /// No description provided for @submittingReview.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirme gönderiliyor...'**
  String get submittingReview;

  /// No description provided for @pleaseProvideRatingAndReview.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir değerlendirme ve yorum metni sağlayın'**
  String get pleaseProvideRatingAndReview;

  /// No description provided for @selectFootwearGender.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet seçin'**
  String get selectFootwearGender;

  /// No description provided for @footwearGender.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet'**
  String get footwearGender;

  /// No description provided for @orderDetails.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Detayları'**
  String get orderDetails;

  /// Sepette kaç öğe var
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =0{Öğe yok} other{# öğe}}'**
  String cartItemsCount(int count);

  /// No description provided for @orderNumber.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş #'**
  String get orderNumber;

  /// No description provided for @unknown.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmiyor'**
  String get unknown;

  /// No description provided for @statusPending.
  ///
  /// In tr, this message translates to:
  /// **'Beklemede'**
  String get statusPending;

  /// No description provided for @statusShipped.
  ///
  /// In tr, this message translates to:
  /// **'Gönderildi'**
  String get statusShipped;

  /// No description provided for @statusDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edildi'**
  String get statusDelivered;

  /// No description provided for @shopSales.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Satışları'**
  String get shopSales;

  /// No description provided for @accessShopSalesDashboard.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza satış panelinize erişin'**
  String get accessShopSalesDashboard;

  /// No description provided for @productsTransferredToBasket.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler baskete taşındı'**
  String get productsTransferredToBasket;

  /// No description provided for @paymentMethods.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Yöntemleri'**
  String get paymentMethods;

  /// No description provided for @deliveryQRCode.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat QR Kodu'**
  String get deliveryQRCode;

  /// No description provided for @showThisToDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Bunu kurye\'ye gösterin'**
  String get showThisToDelivery;

  /// No description provided for @shareQRCode.
  ///
  /// In tr, this message translates to:
  /// **'QR Kodu Paylaş'**
  String get shareQRCode;

  /// No description provided for @failedToLoadQR.
  ///
  /// In tr, this message translates to:
  /// **'QR kodu yüklenemedi'**
  String get failedToLoadQR;

  /// No description provided for @qrGenerating.
  ///
  /// In tr, this message translates to:
  /// **'QR Kodu oluşturuluyor...'**
  String get qrGenerating;

  /// No description provided for @qrGenerationFailed.
  ///
  /// In tr, this message translates to:
  /// **'QR oluşturma başarısız'**
  String get qrGenerationFailed;

  /// No description provided for @qrNotReady.
  ///
  /// In tr, this message translates to:
  /// **'QR Kodu henüz hazır değil'**
  String get qrNotReady;

  /// No description provided for @pleaseWaitQR.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bekleyin...'**
  String get pleaseWaitQR;

  /// No description provided for @tapToRetryQR.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar denemek için dokunun'**
  String get tapToRetryQR;

  /// No description provided for @qrWillBeReady.
  ///
  /// In tr, this message translates to:
  /// **'Kısa sürede hazır olacak'**
  String get qrWillBeReady;

  /// No description provided for @failedToShareQR.
  ///
  /// In tr, this message translates to:
  /// **'QR kodu paylaşılamadı'**
  String get failedToShareQR;

  /// No description provided for @qrRetryInitiated.
  ///
  /// In tr, this message translates to:
  /// **'QR oluşturma yeniden başlatıldı'**
  String get qrRetryInitiated;

  /// No description provided for @failedToRetryQR.
  ///
  /// In tr, this message translates to:
  /// **'QR yeniden oluşturulamadı'**
  String get failedToRetryQR;

  /// No description provided for @viewQRCode.
  ///
  /// In tr, this message translates to:
  /// **'QR Kodu Görüntüle'**
  String get viewQRCode;

  /// No description provided for @orderQRCode.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş QR Kodu'**
  String get orderQRCode;

  /// No description provided for @retrying.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden deneniyor...'**
  String get retrying;

  /// No description provided for @orderDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Teslim Edildi 📦'**
  String get orderDelivered;

  /// No description provided for @ordersDelivered.
  ///
  /// In tr, this message translates to:
  /// **'sipariş teslim edildi'**
  String get ordersDelivered;

  /// No description provided for @inProgress.
  ///
  /// In tr, this message translates to:
  /// **'İşlemde'**
  String get inProgress;

  /// No description provided for @noSavedPaymentMethods.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı ödeme yönteminiz bulunmamaktadır'**
  String get noSavedPaymentMethods;

  /// No description provided for @addNewPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi ekle'**
  String get addNewPaymentMethod;

  /// No description provided for @basketCreated.
  ///
  /// In tr, this message translates to:
  /// **'Basket başarıyla oluşturuldu'**
  String get basketCreated;

  /// No description provided for @basketDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Basket başarıyla silindi'**
  String get basketDeleted;

  /// No description provided for @invalidPriceRange.
  ///
  /// In tr, this message translates to:
  /// **'Minimum fiyat maksimum fiyattan büyük olamaz'**
  String get invalidPriceRange;

  /// No description provided for @allBrands.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Markalar'**
  String get allBrands;

  /// No description provided for @clearColors.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Renkleri Temizle'**
  String get clearColors;

  /// No description provided for @priceRange2.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Aralığı'**
  String get priceRange2;

  /// No description provided for @quickPriceRanges.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Fiyat Aralıkları'**
  String get quickPriceRanges;

  /// No description provided for @minPrice.
  ///
  /// In tr, this message translates to:
  /// **'Minimum Fiyat'**
  String get minPrice;

  /// No description provided for @tryAdjustingFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtrelerinizi ayarlamayı deneyin'**
  String get tryAdjustingFilters;

  /// No description provided for @activeFilters.
  ///
  /// In tr, this message translates to:
  /// **'Aktif filtreler'**
  String get activeFilters;

  /// No description provided for @maxPrice.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum Fiyat'**
  String get maxPrice;

  /// No description provided for @filters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreler'**
  String get filters;

  /// No description provided for @clearBrands.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Markaları Temizle'**
  String get clearBrands;

  /// No description provided for @newPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Yeni ödeme yöntemi'**
  String get newPaymentMethod;

  /// No description provided for @editPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi düzenle'**
  String get editPaymentMethod;

  /// No description provided for @cardHolderName.
  ///
  /// In tr, this message translates to:
  /// **'Kart Sahibinin Adı'**
  String get cardHolderName;

  /// No description provided for @cardNumber.
  ///
  /// In tr, this message translates to:
  /// **'Kart Numarası'**
  String get cardNumber;

  /// No description provided for @expiryDate.
  ///
  /// In tr, this message translates to:
  /// **'Son Kullanma Tarihi'**
  String get expiryDate;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get cancel;

  /// No description provided for @loading.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor...'**
  String get loading;

  /// No description provided for @addFirstPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için ilk ödeme yönteminizi ekleyin'**
  String get addFirstPaymentMethod;

  /// No description provided for @savedCards.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı Kartlar'**
  String get savedCards;

  /// No description provided for @ofFourMethods.
  ///
  /// In tr, this message translates to:
  /// **'/ 4 yöntem'**
  String get ofFourMethods;

  /// No description provided for @addNew.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Ekle'**
  String get addNew;

  /// No description provided for @preferred.
  ///
  /// In tr, this message translates to:
  /// **'Tercih Edilen'**
  String get preferred;

  /// No description provided for @expires.
  ///
  /// In tr, this message translates to:
  /// **'Son Kullanma'**
  String get expires;

  /// No description provided for @maxPaymentMethodsReached.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum 4 ödeme yöntemine izin verilir'**
  String get maxPaymentMethodsReached;

  /// No description provided for @paymentMethodAdded.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi başarıyla eklendi'**
  String get paymentMethodAdded;

  /// No description provided for @paymentMethodUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi başarıyla güncellendi'**
  String get paymentMethodUpdated;

  /// No description provided for @paymentMethodDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi silindi'**
  String get paymentMethodDeleted;

  /// No description provided for @preferredPaymentMethodSet.
  ///
  /// In tr, this message translates to:
  /// **'Tercih edilen ödeme yöntemi ayarlandı'**
  String get preferredPaymentMethodSet;

  /// No description provided for @errorOccurred.
  ///
  /// In tr, this message translates to:
  /// **'An error occurred:'**
  String get errorOccurred;

  /// No description provided for @deletePaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Yöntemini Sil'**
  String get deletePaymentMethod;

  /// No description provided for @deletePaymentMethodConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu ödeme yöntemini silmek istediğinizden emin misiniz?'**
  String get deletePaymentMethodConfirmation;

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @addNewCardDetails.
  ///
  /// In tr, this message translates to:
  /// **'Yeni kart bilgilerinizi ekleyin'**
  String get addNewCardDetails;

  /// No description provided for @updateCardDetails.
  ///
  /// In tr, this message translates to:
  /// **'Kart bilgilerinizi güncelleyin'**
  String get updateCardDetails;

  /// No description provided for @enterCardHolderName.
  ///
  /// In tr, this message translates to:
  /// **'Kart sahibinin adını girin'**
  String get enterCardHolderName;

  /// No description provided for @enterCardNumber.
  ///
  /// In tr, this message translates to:
  /// **'Kart numarasını girin'**
  String get enterCardNumber;

  /// No description provided for @unsupportedCardType.
  ///
  /// In tr, this message translates to:
  /// **'Desteklenmeyen kart türü'**
  String get unsupportedCardType;

  /// No description provided for @savedAddresses.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı adresler'**
  String get savedAddresses;

  /// No description provided for @ofFourAddresses.
  ///
  /// In tr, this message translates to:
  /// **'4 adresden'**
  String get ofFourAddresses;

  /// No description provided for @addFirstAddress.
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için ilk adresinizi ekleyin'**
  String get addFirstAddress;

  /// No description provided for @coordinates.
  ///
  /// In tr, this message translates to:
  /// **'Koordinatlar'**
  String get coordinates;

  /// No description provided for @maxAddressesReached.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum 4 adrese izin verilir'**
  String get maxAddressesReached;

  /// No description provided for @addressAdded.
  ///
  /// In tr, this message translates to:
  /// **'Adres başarıyla eklendi'**
  String get addressAdded;

  /// No description provided for @addressUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Adres başarıyla güncellendi'**
  String get addressUpdated;

  /// No description provided for @addressDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Adres silindi'**
  String get addressDeleted;

  /// No description provided for @deleteAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adresi Sil'**
  String get deleteAddress;

  /// No description provided for @deleteAddressConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu adresi silmek istediğinizden emin misiniz?'**
  String get deleteAddressConfirmation;

  /// No description provided for @preferredAddressSet.
  ///
  /// In tr, this message translates to:
  /// **'Tercih edilen adres ayarlandı'**
  String get preferredAddressSet;

  /// No description provided for @sellerInformation.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Bilgileri'**
  String get sellerInformation;

  /// No description provided for @yourSellerDetails.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı detaylarınız'**
  String get yourSellerDetails;

  /// No description provided for @addSellerInfoDescription.
  ///
  /// In tr, this message translates to:
  /// **'Satış yapmaya başlamak için satıcı bilgilerinizi ekleyin'**
  String get addSellerInfoDescription;

  /// No description provided for @sellerInfoAdded.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgileri başarıyla eklendi'**
  String get sellerInfoAdded;

  /// No description provided for @sellerInfoUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgileri başarıyla güncellendi'**
  String get sellerInfoUpdated;

  /// No description provided for @sellerInfoDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgileri silindi'**
  String get sellerInfoDeleted;

  /// No description provided for @deleteSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Bilgilerini Sil'**
  String get deleteSellerInfo;

  /// No description provided for @deleteSellerInfoConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgilerinizi silmek istediğinizden emin misiniz?'**
  String get deleteSellerInfoConfirmation;

  /// No description provided for @mmYy.
  ///
  /// In tr, this message translates to:
  /// **'AA/YY'**
  String get mmYy;

  /// No description provided for @cvv.
  ///
  /// In tr, this message translates to:
  /// **'CVV'**
  String get cvv;

  /// No description provided for @enterCvv.
  ///
  /// In tr, this message translates to:
  /// **'CVV girin'**
  String get enterCvv;

  /// No description provided for @productsMovedToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler favorilere taşındı'**
  String get productsMovedToFavorites;

  /// No description provided for @productTransferredToBasket.
  ///
  /// In tr, this message translates to:
  /// **'Ürün baskete taşındı'**
  String get productTransferredToBasket;

  /// No description provided for @productMovedToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Ürün favorilere taşındı'**
  String get productMovedToFavorites;

  /// No description provided for @loadingSalesData.
  ///
  /// In tr, this message translates to:
  /// **'Satış verileri yükleniyor...'**
  String get loadingSalesData;

  /// Veri yüklenirken hata mesajı.
  ///
  /// In tr, this message translates to:
  /// **'Veriler yüklenirken hata oluştu'**
  String errorLoadingData(Object error);

  /// No description provided for @unableToLoadSalesInfo.
  ///
  /// In tr, this message translates to:
  /// **'Satış bilgileri yüklenemiyor. Lütfen tekrar deneyin.'**
  String get unableToLoadSalesInfo;

  /// No description provided for @clearAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Temizle'**
  String get clearAll;

  /// No description provided for @confirmClearAllSearchHistory.
  ///
  /// In tr, this message translates to:
  /// **'Arama geçmişinizin hepsini silmek istediğinizden emin misiniz?'**
  String get confirmClearAllSearchHistory;

  /// Arama sırasında ağ bağlantı sorunları olduğunda gösterilen hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantınızı kontrol edin'**
  String get searchNetworkError;

  /// Arama ağ dışı nedenlerle başarısız olduğunda gösterilen genel hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Arama geçici olarak kullanılamıyor'**
  String get searchGeneralError;

  /// Arama başarısız olduğunda tekrar deneme butonu metni
  ///
  /// In tr, this message translates to:
  /// **'Tekrar denemek için dokunun'**
  String get searchRetryButton;

  /// Ürün arama sırasında gösterilen yükleme mesajı
  ///
  /// In tr, this message translates to:
  /// **'Ürünler aranıyor.'**
  String get searchingProducts;

  /// Ağ hataları için kullanıcıdan bağlantısını kontrol etmesini isteyen ek mesaj
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bağlantınızı kontrol edin ve tekrar deneyin'**
  String get searchCheckConnection;

  /// Uygulama çevrimdışı modda olduğunda gösterilen banner metni
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışı mod'**
  String get searchOfflineMode;

  /// Genel hatalar için daha sonra tekrar denemeyi öneren mesaj
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir süre sonra tekrar deneyin'**
  String get searchTryAgainLater;

  /// Hiç internet bağlantısı olmadığında gösterilen mesaj
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı mevcut değil'**
  String get searchNoConnection;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get retry;

  /// No description provided for @noItemsInThisOrder.
  ///
  /// In tr, this message translates to:
  /// **'Bu siparişte ürün yok'**
  String get noItemsInThisOrder;

  /// No description provided for @noShopSalesYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz Mağaza Satışı Yok'**
  String get noShopSalesYet;

  /// No description provided for @campaignSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya Başarılı'**
  String get campaignSuccess;

  /// No description provided for @campaignLinkSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ürünleriniz kampanyaya başarıyla bağlandı!'**
  String get campaignLinkSuccess;

  /// No description provided for @campaignLinkSuccessDescription.
  ///
  /// In tr, this message translates to:
  /// **'Seçtiğiniz ürünler artık kampanyanın bir parçası ve kampanya süresince müşterilere görünür olacak.'**
  String get campaignLinkSuccessDescription;

  /// No description provided for @linkedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanan Ürünler'**
  String get linkedProducts;

  /// No description provided for @productsWithDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirimli Ürünler'**
  String get productsWithDiscount;

  /// No description provided for @averageDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama İndirim'**
  String get averageDiscount;

  /// No description provided for @boostYourProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi Destekleyin'**
  String get boostYourProducts;

  /// No description provided for @reachWiderAudience.
  ///
  /// In tr, this message translates to:
  /// **'Daha geniş kitleye ulaşın ve satışlarınızı artırın'**
  String get reachWiderAudience;

  /// No description provided for @promoteProductsQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi kampanyada tanıtarak daha geniş bir kitleye ulaşmasını ister misiniz?'**
  String get promoteProductsQuestion;

  /// No description provided for @yes.
  ///
  /// In tr, this message translates to:
  /// **'Evet'**
  String get yes;

  /// No description provided for @noThanks.
  ///
  /// In tr, this message translates to:
  /// **'Hayır Teşekkürler'**
  String get noThanks;

  /// Varsayılan kampanya başlığı
  ///
  /// In tr, this message translates to:
  /// **'Kampanya'**
  String get campaign;

  /// No description provided for @campaignSuccessTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya Aktif!'**
  String get campaignSuccessTitle;

  /// No description provided for @campaignSuccessMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi başarıyla kampanyaya dahil ettiniz. Değişiklik yapmak için butona tıklayın.'**
  String get campaignSuccessMessage;

  /// No description provided for @editCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyayı Düzenle'**
  String get editCampaign;

  /// No description provided for @productsInCampaign.
  ///
  /// In tr, this message translates to:
  /// **'kampanyada ürün'**
  String get productsInCampaign;

  /// No description provided for @campaignProducts.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya Ürünleri'**
  String get campaignProducts;

  /// No description provided for @noProductsInCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyada ürün yok'**
  String get noProductsInCampaign;

  /// No description provided for @addProductsToCampaignToGetStarted.
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için bu kampanyaya ürün ekleyin'**
  String get addProductsToCampaignToGetStarted;

  /// No description provided for @noAvailableProducts.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut ürün yok'**
  String get noAvailableProducts;

  /// No description provided for @allProductsAlreadyInCampaigns.
  ///
  /// In tr, this message translates to:
  /// **'Tüm ürünleriniz zaten kampanyalarda'**
  String get allProductsAlreadyInCampaigns;

  /// Seçimi temizleme düğmesi metni
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clear;

  /// No description provided for @removeFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyadan çıkar'**
  String get removeFromCampaign;

  /// İndirim yüzdesi giriş alanı etiketi
  ///
  /// In tr, this message translates to:
  /// **'İndirim Yüzdesi'**
  String get discountPercentage;

  /// No description provided for @min.
  ///
  /// In tr, this message translates to:
  /// **'Min'**
  String get min;

  /// No description provided for @max.
  ///
  /// In tr, this message translates to:
  /// **'Maks'**
  String get max;

  /// No description provided for @update.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get update;

  /// No description provided for @add.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get add;

  /// No description provided for @products.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler'**
  String get products;

  /// No description provided for @adding.
  ///
  /// In tr, this message translates to:
  /// **'Ekleniyor...'**
  String get adding;

  /// No description provided for @removeProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü kaldır'**
  String get removeProduct;

  /// No description provided for @areYouSureRemoveProduct.
  ///
  /// In tr, this message translates to:
  /// **'Emin misiniz'**
  String get areYouSureRemoveProduct;

  /// No description provided for @fromThisCampaign.
  ///
  /// In tr, this message translates to:
  /// **'ürününü bu kampanyadan çıkarmak istediğinizden'**
  String get fromThisCampaign;

  /// No description provided for @remove.
  ///
  /// In tr, this message translates to:
  /// **'Kaldır'**
  String get remove;

  /// No description provided for @productRemovedFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kampanyadan çıkarıldı'**
  String get productRemovedFromCampaign;

  /// No description provided for @failedToRemoveProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün çıkarılamadı'**
  String get failedToRemoveProduct;

  /// No description provided for @failedToUpdateDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim güncellenemedi'**
  String get failedToUpdateDiscount;

  /// No description provided for @pleaseSelectProductsToAdd.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen eklenecek ürünleri seçin'**
  String get pleaseSelectProductsToAdd;

  /// No description provided for @productsAddedToCampaign.
  ///
  /// In tr, this message translates to:
  /// **'ürün kampanyaya eklendi'**
  String get productsAddedToCampaign;

  /// No description provided for @failedToAddProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler eklenemedi'**
  String get failedToAddProducts;

  /// No description provided for @invalidDiscountPercentage.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz indirim yüzdesi'**
  String get invalidDiscountPercentage;

  /// Arama girdi alanının yer tutucu metni
  ///
  /// In tr, this message translates to:
  /// **'Ürün, marka, kategori ara...'**
  String get searchProductsBrandsCategories;

  /// Mevcut ürün sayısını gösterir
  ///
  /// In tr, this message translates to:
  /// **'{count} ürün'**
  String productsCount(int count);

  /// Görünür tüm ürünleri seçme düğmesi metni
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Seç'**
  String get selectAll;

  /// Stokta olmayan ürünlerde gösterilen etiket
  ///
  /// In tr, this message translates to:
  /// **'Stokta Yok'**
  String get outOfStock;

  /// Arama sonuç döndürmediğinde öneri metni
  ///
  /// In tr, this message translates to:
  /// **'Arama terimlerinizi veya filtrelerinizi ayarlamayı deneyin'**
  String get tryAdjustingSearchTerms;

  /// Mağazada ürün olmadığında öneri metni
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için mağazanıza ürün ekleyin'**
  String get addProductsToShop;

  /// Arama sorgusunu temizleme düğmesi metni
  ///
  /// In tr, this message translates to:
  /// **'Aramayı Temizle'**
  String get clearSearch;

  /// Ürün seçmeden devam etmeye çalışırken gösterilen hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir ürün seçin'**
  String get selectAtLeastOneProduct;

  /// Seçilen ürün sayısını gösteren devam düğmesi metni
  ///
  /// In tr, this message translates to:
  /// **'{count} ürün{count, plural, =1{} other{}} ile devam et'**
  String continueWithProducts(int count);

  /// Ürün indirimleri yapılandırma ekranı başlığı
  ///
  /// In tr, this message translates to:
  /// **'İndirim Yapılandırması'**
  String get configureDiscounts;

  /// Toplu indirim bölümü başlığı
  ///
  /// In tr, this message translates to:
  /// **'Toplu indirim'**
  String get bulkDiscount;

  /// Toplu indirim bölümü alt başlığı
  ///
  /// In tr, this message translates to:
  /// **'Tüm ürünlere aynı indirim uygula'**
  String get applySameDiscountToAllProducts;

  /// İndirim girişi için örnek metin
  ///
  /// In tr, this message translates to:
  /// **'örn: 15,5'**
  String get exampleDiscount;

  /// İndirim aralığını gösteren yardım metni
  ///
  /// In tr, this message translates to:
  /// **'Aralık: %{min} - %{max}'**
  String discountRange(double min, double max);

  /// Toplu indirimi uygulamak için düğme metni
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get apply;

  /// Toplam ürün istatistiği etiketi
  ///
  /// In tr, this message translates to:
  /// **'Toplam Ürün'**
  String get totalProducts;

  /// İndirimli ürünler istatistiği etiketi
  ///
  /// In tr, this message translates to:
  /// **'İndirimli'**
  String get withDiscount;

  /// İndirimsiz ürünler istatistiği etiketi
  ///
  /// In tr, this message translates to:
  /// **'İndirimsiz'**
  String get noDiscount;

  /// Bireysel ürün indirim girişi etiketi
  ///
  /// In tr, this message translates to:
  /// **'İndirim'**
  String get discount;

  /// Toplu indirim alanı boş olduğunda hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir indirim yüzdesi girin'**
  String get pleaseEnterDiscountPercentage;

  /// Geçersiz indirim aralığı için hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'İndirim %{min} ile %{max} arasında olmalıdır'**
  String discountRangeError(double min, double max);

  /// Toplu indirim uygulandıktan sonra başarı mesajı
  ///
  /// In tr, this message translates to:
  /// **'Toplu indirim {count} ürüne uygulandı'**
  String bulkDiscountApplied(int count);

  /// Tüm ürünlerde indirim olmadan devam etmeye çalışırken hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için tüm ürünlerde indirim olmalıdır'**
  String get allProductsMustHaveDiscount;

  /// Geçersiz bireysel indirimler için hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Bazı indirimler geçersiz. %{min} ile %{max} arasında olmalıdır'**
  String someDiscountsInvalid(double min, double max);

  /// Kampanya kaydetme başarısız olduğunda hata mesajı
  ///
  /// In tr, this message translates to:
  /// **'Kampanya kaydedilemedi: {error}'**
  String failedToSaveCampaign(String error);

  /// Hata snackbar'ını kapatmak için düğme metni
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get dismiss;

  /// Kampanya kaydedilirken yükleme metni
  ///
  /// In tr, this message translates to:
  /// **'Kampanya Kaydediliyor...'**
  String get savingCampaign;

  /// Sonraki ekrana devam etmek için düğme metni
  ///
  /// In tr, this message translates to:
  /// **'Özete Devam Et'**
  String get continueToSummary;

  /// No description provided for @orderDoesntContainShopItems.
  ///
  /// In tr, this message translates to:
  /// **'Bu sipariş mağazanızdan hiçbir ürün içermiyor.'**
  String get orderDoesntContainShopItems;

  /// No description provided for @soldProductsWillAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Sattığınız ürünler burada görünecek'**
  String get soldProductsWillAppearHere;

  /// No description provided for @buyer.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı'**
  String get buyer;

  /// No description provided for @qty.
  ///
  /// In tr, this message translates to:
  /// **'Adet'**
  String get qty;

  /// No description provided for @ship.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get ship;

  /// No description provided for @completed.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlandı'**
  String get completed;

  /// No description provided for @statusCancelled.
  ///
  /// In tr, this message translates to:
  /// **'İptal Edildi'**
  String get statusCancelled;

  /// No description provided for @items.
  ///
  /// In tr, this message translates to:
  /// **'ürün'**
  String get items;

  /// No description provided for @unknownProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Ürün'**
  String get unknownProduct;

  /// No description provided for @soldBy.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı:'**
  String get soldBy;

  /// No description provided for @size.
  ///
  /// In tr, this message translates to:
  /// **'Beden'**
  String get size;

  /// No description provided for @shippingAddress.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Adresi'**
  String get shippingAddress;

  /// No description provided for @orderSummary.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Özeti'**
  String get orderSummary;

  /// No description provided for @shipping.
  ///
  /// In tr, this message translates to:
  /// **'Kargo'**
  String get shipping;

  /// No description provided for @free.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz'**
  String get free;

  /// No description provided for @total.
  ///
  /// In tr, this message translates to:
  /// **'Toplam'**
  String get total;

  /// No description provided for @failedToLoadOrder.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş detayları yüklenemedi'**
  String get failedToLoadOrder;

  /// No description provided for @orderDate.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Tarihi'**
  String get orderDate;

  /// No description provided for @paymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Yöntemi'**
  String get paymentMethod;

  /// No description provided for @errorUpdatingStatus.
  ///
  /// In tr, this message translates to:
  /// **'Durum güncellenirken hata oluştu'**
  String get errorUpdatingStatus;

  /// No description provided for @shipmentStatusUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Kargo durumu başarıyla güncellendi'**
  String get shipmentStatusUpdated;

  /// No description provided for @confirmShipmentMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü kargoya verildi olarak işaretlemek istediğinizden emin misiniz?'**
  String get confirmShipmentMessage;

  /// No description provided for @cancelled.
  ///
  /// In tr, this message translates to:
  /// **'İptal Edildi'**
  String get cancelled;

  /// No description provided for @delivered.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edildi'**
  String get delivered;

  /// No description provided for @unknownDate.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Tarih'**
  String get unknownDate;

  /// No description provided for @noSoldProductsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz satılan ürün yok'**
  String get noSoldProductsYet;

  /// No description provided for @pleaseSignIn.
  ///
  /// In tr, this message translates to:
  /// **'Sattığınız ürünleri görmek için giriş yapın'**
  String get pleaseSignIn;

  /// No description provided for @orderItemsWillAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş ürünleri burada görünecek'**
  String get orderItemsWillAppearHere;

  /// No description provided for @footwearSizes.
  ///
  /// In tr, this message translates to:
  /// **'Bedenler'**
  String get footwearSizes;

  /// No description provided for @selectFootwearSizes.
  ///
  /// In tr, this message translates to:
  /// **'Boyut Seçiniz'**
  String get selectFootwearSizes;

  /// No description provided for @pleaseSelectAllDetails.
  ///
  /// In tr, this message translates to:
  /// **'Seçeneklerden en az bir tanesini seçiniz'**
  String get pleaseSelectAllDetails;

  /// No description provided for @productOutOfStockSellerPanel.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızdaki ürün stokta kalmadı!'**
  String get productOutOfStockSellerPanel;

  /// No description provided for @listProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün listele'**
  String get listProduct;

  /// No description provided for @viewShopDetail.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan detaylarını görüntüle'**
  String get viewShopDetail;

  /// No description provided for @welcomeBack.
  ///
  /// In tr, this message translates to:
  /// **'Hoşgeldiniz'**
  String get welcomeBack;

  /// No description provided for @boughtProducts.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alınan'**
  String get boughtProducts;

  /// No description provided for @applyDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim Uygula'**
  String get applyDiscount;

  /// No description provided for @collectionCreatedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon başarıyla oluşturuldu'**
  String get collectionCreatedSuccess;

  /// No description provided for @collectionUpdatedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon başarıyla güncellendi'**
  String get collectionUpdatedSuccess;

  /// No description provided for @collectionDeletedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon başarıyla silindi'**
  String get collectionDeletedSuccess;

  /// No description provided for @collectionCreatedError.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon oluşturulamadı'**
  String get collectionCreatedError;

  /// No description provided for @collectionUpdatedError.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon güncellenemedi'**
  String get collectionUpdatedError;

  /// No description provided for @collectionDeletedError.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon silinemedi'**
  String get collectionDeletedError;

  /// No description provided for @loadCollectionsError.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonlar yüklenemedi'**
  String get loadCollectionsError;

  /// No description provided for @imageSizeError.
  ///
  /// In tr, this message translates to:
  /// **'Resim boyutu 20MB\'dan küçük olmalıdır'**
  String get imageSizeError;

  /// No description provided for @imageUploadError.
  ///
  /// In tr, this message translates to:
  /// **'Resim yüklenemedi'**
  String get imageUploadError;

  /// No description provided for @seeFromThisCollection.
  ///
  /// In tr, this message translates to:
  /// **'Bu koleksiyondan daha fazla'**
  String get seeFromThisCollection;

  /// No description provided for @collection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon'**
  String get collection;

  /// No description provided for @filtersApplied.
  ///
  /// In tr, this message translates to:
  /// **'filtre uygulandı'**
  String get filtersApplied;

  /// No description provided for @pleaseSelectShop.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir mağaza seçin'**
  String get pleaseSelectShop;

  /// No description provided for @searchFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerde Ara'**
  String get searchFavorites;

  /// No description provided for @pauseSale.
  ///
  /// In tr, this message translates to:
  /// **'Arşivle'**
  String get pauseSale;

  /// No description provided for @archived.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen'**
  String get archived;

  /// No description provided for @archivedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen Ürünler'**
  String get archivedProducts;

  /// No description provided for @archivedProductsManager.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen Ürünler Yöneticisi'**
  String get archivedProductsManager;

  /// No description provided for @archivedProductsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen (duraklatılan) ürünlerinizi görüntüleyin ve yönetin. Ürünleri arşivden çıkararak tekrar satışa sunabilirsiniz.'**
  String get archivedProductsDescription;

  /// No description provided for @searchArchivedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen ürünlerde ara...'**
  String get searchArchivedProducts;

  /// No description provided for @unarchive.
  ///
  /// In tr, this message translates to:
  /// **'Arşivden Çıkar'**
  String get unarchive;

  /// No description provided for @boostExpiredAdminArchived.
  ///
  /// In tr, this message translates to:
  /// **'\"{productName}\" boost süresi, ürün admin tarafından durdurulduğu için erken sonlandırıldı.'**
  String boostExpiredAdminArchived(Object productName);

  /// No description provided for @boostExpiredSellerArchived.
  ///
  /// In tr, this message translates to:
  /// **'\"{productName}\" boost süresi, ürün arşivlendiği için erken sonlandırıldı.'**
  String boostExpiredSellerArchived(Object productName);

  /// No description provided for @boostExpiredGeneric.
  ///
  /// In tr, this message translates to:
  /// **'\"{productName}\" boost süresi doldu.'**
  String boostExpiredGeneric(Object productName);

  /// No description provided for @boostInfoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi Öne Çıkarın'**
  String get boostInfoTitle;

  /// No description provided for @boostTerminatedEarlyAdmin.
  ///
  /// In tr, this message translates to:
  /// **'Boost, ürün admin tarafından durdurulduğu için erken sonlandırıldı.'**
  String get boostTerminatedEarlyAdmin;

  /// No description provided for @boostTerminatedEarlySeller.
  ///
  /// In tr, this message translates to:
  /// **'Boost, ürün arşivlendiği için erken sonlandırıldı.'**
  String get boostTerminatedEarlySeller;

  /// No description provided for @productArchivedSimple.
  ///
  /// In tr, this message translates to:
  /// **'\"{productName}\" admin tarafından durduruldu.'**
  String productArchivedSimple(Object productName);

  /// No description provided for @productArchivedNeedsUpdate.
  ///
  /// In tr, this message translates to:
  /// **'\"{productName}\" admin tarafından durduruldu ve güncelleme gerekiyor: {archiveReason}'**
  String productArchivedNeedsUpdate(Object archiveReason, Object productName);

  /// No description provided for @productArchivedBoostNote.
  ///
  /// In tr, this message translates to:
  /// **'Aktif boost da erken sonlandırıldı.'**
  String get productArchivedBoostNote;

  /// No description provided for @activeBoostWarningTitle.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Boost'**
  String get activeBoostWarningTitle;

  /// No description provided for @activeBoostWarningMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünün aktif bir boost süresi var. Devam ederseniz boost erken sonlandırılacaktır. Devam etmek istiyor musunuz?'**
  String get activeBoostWarningMessage;

  /// No description provided for @boostInfoDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerinizi öne çıkararak daha geniş kitlelere ulaşın ve arama sonuçlarında görünürlüğünüzü artırın. Daha fazla görüntülenme ve potansiyel alıcı elde edin!'**
  String get boostInfoDescription;

  /// No description provided for @noProductsToBoostTitle.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkarılacak Ürün Yok'**
  String get noProductsToBoostTitle;

  /// No description provided for @noProductsToBoostDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz öne çıkarılacak ürününüz bulunmuyor. Reklamcılığa başlamak için önce birkaç ürün ekleyin.'**
  String get noProductsToBoostDescription;

  /// No description provided for @addProductFirst.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Ekle'**
  String get addProductFirst;

  /// No description provided for @adApproved2.
  ///
  /// In tr, this message translates to:
  /// **'{adType} reklam başvurunuz onaylandı.'**
  String adApproved2(String adType);

  /// No description provided for @adRejected2.
  ///
  /// In tr, this message translates to:
  /// **'{adType} reklam başvurunuz reddedildi.'**
  String adRejected2(String adType);

  /// No description provided for @salesPausedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satışlar Geçici Olarak Durduruldu'**
  String get salesPausedTitle;

  /// No description provided for @salesPausedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda sipariş almıyoruz. Lütfen daha sonra tekrar deneyin.'**
  String get salesPausedMessage;

  /// No description provided for @salesTemporarilyPaused.
  ///
  /// In tr, this message translates to:
  /// **'Satışlar geçici olarak durduruldu'**
  String get salesTemporarilyPaused;

  /// No description provided for @checkoutPaused.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Durduruldu'**
  String get checkoutPaused;

  /// No description provided for @understood.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get understood;

  /// No description provided for @questionAnswered.
  ///
  /// In tr, this message translates to:
  /// **'Soru Yanıtlandı 💬'**
  String get questionAnswered;

  /// No description provided for @unarchiveProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü Arşivden Çıkar'**
  String get unarchiveProduct;

  /// No description provided for @pendingPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Bekliyor'**
  String get pendingPayment;

  /// No description provided for @adExpired.
  ///
  /// In tr, this message translates to:
  /// **'{adType} reklamınızın süresi doldu.'**
  String adExpired(Object adType);

  /// No description provided for @bulkDiscountFieldsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Miktar eşiği ve indirim yüzdesi birlikte ayarlanmalıdır'**
  String get bulkDiscountFieldsRequired;

  /// No description provided for @unarchiveProductConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün aktif ürünlere geri taşınacak ve satışa sunulacak.'**
  String get unarchiveProductConfirmation;

  /// No description provided for @unarchivingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün arşivden çıkarılıyor...'**
  String get unarchivingProduct;

  /// No description provided for @productUnarchivedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla arşivden çıkarıldı ve artık satışa sunuluyor'**
  String get productUnarchivedSuccess;

  /// No description provided for @productsSelectedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} Ürün Seçildi'**
  String productsSelectedCount(int count);

  /// No description provided for @productNeedsUpdate.
  ///
  /// In tr, this message translates to:
  /// **'Güncelleme Gerekli'**
  String get productNeedsUpdate;

  /// No description provided for @archivedByAdmin.
  ///
  /// In tr, this message translates to:
  /// **'Admin tarafından arşivlendi'**
  String get archivedByAdmin;

  /// No description provided for @adminMessage.
  ///
  /// In tr, this message translates to:
  /// **'Admin Mesajı'**
  String get adminMessage;

  /// No description provided for @contactSupportToUnarchive.
  ///
  /// In tr, this message translates to:
  /// **'Arşivden çıkarmak için destek ile iletişime geçin'**
  String get contactSupportToUnarchive;

  /// No description provided for @productArchivedByAdminCannotUnarchive.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün bir yönetici tarafından arşivlenmiştir. Daha fazla bilgi için destek ile iletişime geçin.'**
  String get productArchivedByAdminCannotUnarchive;

  /// No description provided for @updateAndResubmit.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle ve Tekrar Gönder'**
  String get updateAndResubmit;

  /// No description provided for @productUpdateSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Ürün güncellemesi onay için gönderildi'**
  String get productUpdateSubmitted;

  /// No description provided for @collectionProductLimitReached.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon başına en fazla 50 ürün'**
  String get collectionProductLimitReached;

  /// No description provided for @productUnarchiveError.
  ///
  /// In tr, this message translates to:
  /// **'Ürün arşivden çıkarılamadı. Lütfen tekrar deneyin.'**
  String get productUnarchiveError;

  /// No description provided for @noArchivedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen ürün yok'**
  String get noArchivedProducts;

  /// No description provided for @noArchivedProductsFound.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenen ürün bulunamadı'**
  String get noArchivedProductsFound;

  /// No description provided for @archivedProductsEmptyDescription.
  ///
  /// In tr, this message translates to:
  /// **'Arşivlenmiş ürününüz bulunmuyor. Ana ürünler sekmesinden ürünleri duraklattığınızda burada görünecekler.'**
  String get archivedProductsEmptyDescription;

  /// No description provided for @tryDifferentSearchTerm.
  ///
  /// In tr, this message translates to:
  /// **'Aradığınızı bulmak için farklı arama terimleri kullanmayı deneyin.'**
  String get tryDifferentSearchTerm;

  /// No description provided for @archiveProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü Arşivle'**
  String get archiveProduct;

  /// No description provided for @archiveProductConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün arşivlenen ürünlere taşınacak ve satışa sunulmayacak.'**
  String get archiveProductConfirmation;

  /// No description provided for @archivingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün arşivleniyor...'**
  String get archivingProduct;

  /// No description provided for @productArchivedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla arşivlendi'**
  String get productArchivedSuccess;

  /// No description provided for @productArchiveError.
  ///
  /// In tr, this message translates to:
  /// **'Ürün arşivlenemedi. Lütfen tekrar deneyin.'**
  String get productArchiveError;

  /// No description provided for @failedToLoadRecommendations.
  ///
  /// In tr, this message translates to:
  /// **'Size özel ürünler yüklenirken hata'**
  String get failedToLoadRecommendations;

  /// No description provided for @archive.
  ///
  /// In tr, this message translates to:
  /// **'Arşivle'**
  String get archive;

  /// No description provided for @failedToLoadBoostedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkanlarda hata'**
  String get failedToLoadBoostedProducts;

  /// No description provided for @versionCheckUpdateAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Güncelleme Mevcut'**
  String get versionCheckUpdateAvailable;

  /// No description provided for @versionCheckUpdateRequired.
  ///
  /// In tr, this message translates to:
  /// **'Güncelleme Gerekli'**
  String get versionCheckUpdateRequired;

  /// No description provided for @versionCheckMaintenance.
  ///
  /// In tr, this message translates to:
  /// **'Bakım Çalışması'**
  String get versionCheckMaintenance;

  /// No description provided for @versionCheckUpToDate.
  ///
  /// In tr, this message translates to:
  /// **'Güncel'**
  String get versionCheckUpToDate;

  /// No description provided for @versionCheckUpdateNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Güncelle'**
  String get versionCheckUpdateNow;

  /// No description provided for @versionCheckLater.
  ///
  /// In tr, this message translates to:
  /// **'Daha Sonra'**
  String get versionCheckLater;

  /// No description provided for @versionCheckCloseApp.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı Kapat'**
  String get versionCheckCloseApp;

  /// No description provided for @versionCheckWhatsNew.
  ///
  /// In tr, this message translates to:
  /// **'Yenilikler'**
  String get versionCheckWhatsNew;

  /// No description provided for @versionCheckEstimatedTime.
  ///
  /// In tr, this message translates to:
  /// **'TAHMİNİ KALAN SÜRE'**
  String get versionCheckEstimatedTime;

  /// No description provided for @versionCheckHours.
  ///
  /// In tr, this message translates to:
  /// **'saat'**
  String get versionCheckHours;

  /// No description provided for @versionCheckMinutes.
  ///
  /// In tr, this message translates to:
  /// **'dk'**
  String get versionCheckMinutes;

  /// No description provided for @versionCheckSeconds.
  ///
  /// In tr, this message translates to:
  /// **'sn'**
  String get versionCheckSeconds;

  /// No description provided for @versionCheckStoreError.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza açılamadı. Lütfen tekrar deneyin.'**
  String get versionCheckStoreError;

  /// No description provided for @versionCheckUpdateDefault.
  ///
  /// In tr, this message translates to:
  /// **'Yeni bir sürüm mevcut. En iyi deneyim için şimdi güncelleyin.'**
  String get versionCheckUpdateDefault;

  /// No description provided for @versionCheckMaintenanceDefault.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda bakım yapıyoruz. Lütfen daha sonra tekrar deneyin.'**
  String get versionCheckMaintenanceDefault;

  /// No description provided for @boostedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkan Ürünler'**
  String get boostedProducts;

  /// No description provided for @deleteProductPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü silmek istiyor musunuz?'**
  String get deleteProductPrompt;

  /// No description provided for @pickFromGallery.
  ///
  /// In tr, this message translates to:
  /// **'Galeriden Seç'**
  String get pickFromGallery;

  /// No description provided for @off.
  ///
  /// In tr, this message translates to:
  /// **'İNDİRİM'**
  String get off;

  /// No description provided for @productGallery.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Galerisi'**
  String get productGallery;

  /// No description provided for @productAnalytics.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Analitiği'**
  String get productAnalytics;

  /// No description provided for @availableInStock.
  ///
  /// In tr, this message translates to:
  /// **'Stokta mevcut'**
  String get availableInStock;

  /// No description provided for @maximumQuantityLimit.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum Miktar Sınırı'**
  String get maximumQuantityLimit;

  /// No description provided for @bulkPurchaseDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Toplu Alım İndirimi'**
  String get bulkPurchaseDiscount;

  /// No description provided for @applyDiscountOf.
  ///
  /// In tr, this message translates to:
  /// **'İndirim uygula'**
  String get applyDiscountOf;

  /// No description provided for @applyingDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim uygulanıyor'**
  String get applyingDiscount;

  /// No description provided for @removingDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim kaldırılıyor'**
  String get removingDiscount;

  /// No description provided for @captureVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video Çek'**
  String get captureVideo;

  /// No description provided for @capturePhoto.
  ///
  /// In tr, this message translates to:
  /// **'Resim Çek'**
  String get capturePhoto;

  /// No description provided for @noSearchHistory.
  ///
  /// In tr, this message translates to:
  /// **'Arama geçmişi bulunmamaktadır'**
  String get noSearchHistory;

  /// No description provided for @login.
  ///
  /// In tr, this message translates to:
  /// **'İlk Önce Giriş Yapmanız Gerekiyor'**
  String get login;

  /// No description provided for @login2.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get login2;

  /// No description provided for @myProductApplications.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Başvurularım'**
  String get myProductApplications;

  /// No description provided for @pleaseLoginToViewApplications.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başvurularınızı görmek için lütfen giriş yapın'**
  String get pleaseLoginToViewApplications;

  /// No description provided for @noVitrinApplicationsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ürün başvurusu yapmadınız. İlk ürününüzü listeleyerek satışa başlayın!'**
  String get noVitrinApplicationsDescription;

  /// No description provided for @listNewProduct.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Ürün Listele'**
  String get listNewProduct;

  /// No description provided for @loginWithEmailandPassword.
  ///
  /// In tr, this message translates to:
  /// **'Eposta ve şifre ile giriş yap'**
  String get loginWithEmailandPassword;

  /// No description provided for @noStock.
  ///
  /// In tr, this message translates to:
  /// **'Stokta Kalmadı'**
  String get noStock;

  /// No description provided for @askToSellerAcceptTermsError.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen Kullanıcı Sözleşmesi’ni kabul edin.'**
  String get askToSellerAcceptTermsError;

  /// No description provided for @askToSellerEmptyQuestionError.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir soru yazın.'**
  String get askToSellerEmptyQuestionError;

  /// No description provided for @askToSellerNoUserError.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı oturumu mevcut değil.'**
  String get askToSellerNoUserError;

  /// No description provided for @noQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi bir ürün sorusu bulunmamaktadır.'**
  String get noQuestions;

  /// No description provided for @from.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get from;

  /// No description provided for @to.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get to;

  /// No description provided for @answered.
  ///
  /// In tr, this message translates to:
  /// **'Cevaplanan'**
  String get answered;

  /// No description provided for @nothingToReview.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirilecek ürün bulunmamaktadır'**
  String get nothingToReview;

  /// No description provided for @youHaveNoReviews.
  ///
  /// In tr, this message translates to:
  /// **'Henüz değerlendirmeniz bulunmamaktadır'**
  String get youHaveNoReviews;

  /// No description provided for @noAnsweredQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Henüz cevaplanmış soru bulunmamaktadır'**
  String get noAnsweredQuestions;

  /// No description provided for @noReceivedReviews.
  ///
  /// In tr, this message translates to:
  /// **'Henüz değerlendirme alınmadı'**
  String get noReceivedReviews;

  /// No description provided for @selectJewelryType.
  ///
  /// In tr, this message translates to:
  /// **'Tür Seçin'**
  String get selectJewelryType;

  /// No description provided for @selectJewelryMaterial.
  ///
  /// In tr, this message translates to:
  /// **'Materyal Seçin'**
  String get selectJewelryMaterial;

  /// No description provided for @clothingMaterial.
  ///
  /// In tr, this message translates to:
  /// **'Materyal'**
  String get clothingMaterial;

  /// No description provided for @jewelryTypeNecklace.
  ///
  /// In tr, this message translates to:
  /// **'Kolye'**
  String get jewelryTypeNecklace;

  /// No description provided for @jewelryTypeEarring.
  ///
  /// In tr, this message translates to:
  /// **'Küpe'**
  String get jewelryTypeEarring;

  /// No description provided for @jewelryTypePiercing.
  ///
  /// In tr, this message translates to:
  /// **'Piercing'**
  String get jewelryTypePiercing;

  /// No description provided for @stockValidationError.
  ///
  /// In tr, this message translates to:
  /// **'Stok problemi'**
  String get stockValidationError;

  /// No description provided for @itemsAddedToCart.
  ///
  /// In tr, this message translates to:
  /// **'{count} ürün sepete eklendi'**
  String itemsAddedToCart(Object count);

  /// No description provided for @consoleVariant.
  ///
  /// In tr, this message translates to:
  /// **'Konsol Türü'**
  String get consoleVariant;

  /// No description provided for @computerComponent.
  ///
  /// In tr, this message translates to:
  /// **'Parça'**
  String get computerComponent;

  /// No description provided for @consoleBrand.
  ///
  /// In tr, this message translates to:
  /// **'Konsol'**
  String get consoleBrand;

  /// No description provided for @kitchenAppliance.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz'**
  String get kitchenAppliance;

  /// No description provided for @whiteGood.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz Eşya'**
  String get whiteGood;

  /// No description provided for @submitEdit.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get submitEdit;

  /// No description provided for @previewEditProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Güncelleme'**
  String get previewEditProduct;

  /// No description provided for @rejectionReason.
  ///
  /// In tr, this message translates to:
  /// **'Ret Sebebi'**
  String get rejectionReason;

  /// No description provided for @productEditRejected.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Düzenleme Reddedildi'**
  String get productEditRejected;

  /// No description provided for @productEditRejectedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ürün düzenleme başvurunuz reddedildi.'**
  String get productEditRejectedMessage;

  /// No description provided for @productEditApproved.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Düzenleme Onaylandı'**
  String get productEditApproved;

  /// No description provided for @jewelryTypeRing.
  ///
  /// In tr, this message translates to:
  /// **'Yüzük'**
  String get jewelryTypeRing;

  /// No description provided for @jewelryTypeBracelet.
  ///
  /// In tr, this message translates to:
  /// **'Bilezik'**
  String get jewelryTypeBracelet;

  /// No description provided for @jewelryTypeAnklet.
  ///
  /// In tr, this message translates to:
  /// **'Ayak bileziği'**
  String get jewelryTypeAnklet;

  /// No description provided for @jewelryTypeNoseRing.
  ///
  /// In tr, this message translates to:
  /// **'Burun halkası'**
  String get jewelryTypeNoseRing;

  /// No description provided for @jewelryMaterialIron.
  ///
  /// In tr, this message translates to:
  /// **'Demir'**
  String get jewelryMaterialIron;

  /// No description provided for @jewelryMaterialSteel.
  ///
  /// In tr, this message translates to:
  /// **'Çelik'**
  String get jewelryMaterialSteel;

  /// No description provided for @jewelryMaterialGold.
  ///
  /// In tr, this message translates to:
  /// **'Altın'**
  String get jewelryMaterialGold;

  /// No description provided for @jewelryMaterialSilver.
  ///
  /// In tr, this message translates to:
  /// **'Gümüş'**
  String get jewelryMaterialSilver;

  /// No description provided for @jewelryMaterialDiamond.
  ///
  /// In tr, this message translates to:
  /// **'Elmas'**
  String get jewelryMaterialDiamond;

  /// No description provided for @jewelryMaterialCopper.
  ///
  /// In tr, this message translates to:
  /// **'Bakır'**
  String get jewelryMaterialCopper;

  /// No description provided for @jewelryType.
  ///
  /// In tr, this message translates to:
  /// **'Takı Türü'**
  String get jewelryType;

  /// No description provided for @jewelryMaterial.
  ///
  /// In tr, this message translates to:
  /// **'Takı Materyali'**
  String get jewelryMaterial;

  /// No description provided for @jewelryTypeSet.
  ///
  /// In tr, this message translates to:
  /// **'Set'**
  String get jewelryTypeSet;

  /// No description provided for @askToSellerSubmitError.
  ///
  /// In tr, this message translates to:
  /// **'Soru gönderilirken hata oluştu'**
  String get askToSellerSubmitError;

  /// No description provided for @askToSellerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satıcıya Sor'**
  String get askToSellerTitle;

  /// No description provided for @askToSellerNoSellerError.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgileri yüklenemedi.'**
  String get askToSellerNoSellerError;

  /// No description provided for @askToSellerInfoStart.
  ///
  /// In tr, this message translates to:
  /// **'Siparişinle ilgili sorularını '**
  String get askToSellerInfoStart;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu sohbeti silmek istediğinizden emin misiniz?'**
  String get confirmDeleteMessage;

  /// No description provided for @askToSellerInfoOrdersLink.
  ///
  /// In tr, this message translates to:
  /// **'“Siparişlerim”'**
  String get askToSellerInfoOrdersLink;

  /// No description provided for @askToSellerInfoEnd.
  ///
  /// In tr, this message translates to:
  /// **' sayfasından takip edebilirsiniz!'**
  String get askToSellerInfoEnd;

  /// No description provided for @askToSellerQuestionLabel.
  ///
  /// In tr, this message translates to:
  /// **'Soru Sor'**
  String get askToSellerQuestionLabel;

  /// No description provided for @askToSellerCriteriaLink.
  ///
  /// In tr, this message translates to:
  /// **'Yayınlanma Kriterleri'**
  String get askToSellerCriteriaLink;

  /// No description provided for @toReview.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendireceklerim'**
  String get toReview;

  /// No description provided for @myRatings.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirdiklerim'**
  String get myRatings;

  /// No description provided for @productReviews.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Değerlendirmeleri'**
  String get productReviews;

  /// No description provided for @shopReviews.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Değerlendirmeleri'**
  String get shopReviews;

  /// No description provided for @noProductReviews.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir ürün yorumu bulunmamaktadır'**
  String get noProductReviews;

  /// No description provided for @noShopReviews.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir dükkan yorumu bulunmamaktadır'**
  String get noShopReviews;

  /// No description provided for @askToSellerQuestionHint.
  ///
  /// In tr, this message translates to:
  /// **'Sorunuzu buraya yazın'**
  String get askToSellerQuestionHint;

  /// No description provided for @askToSellerNameVisibility.
  ///
  /// In tr, this message translates to:
  /// **'Sorumda ad-soyadı bilgimin görünmesine izin veriyorum.'**
  String get askToSellerNameVisibility;

  /// No description provided for @askToSellerAcceptTermsPrefix.
  ///
  /// In tr, this message translates to:
  /// **'Soru sormak için '**
  String get askToSellerAcceptTermsPrefix;

  /// No description provided for @askToSellerAcceptTermsLink.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Sözleşmesi’ni kabul ediyorum'**
  String get askToSellerAcceptTermsLink;

  /// No description provided for @askToSellerSend.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get askToSellerSend;

  /// No description provided for @selectBirthDate.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Gününüzü Seçiniz'**
  String get selectBirthDate;

  /// No description provided for @signInWithGoogle.
  ///
  /// In tr, this message translates to:
  /// **'Google ile giriş yap'**
  String get signInWithGoogle;

  /// No description provided for @footwearDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ayakkabı Detayları'**
  String get footwearDetails;

  /// No description provided for @initializationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu'**
  String get initializationFailed;

  /// No description provided for @allQuestionsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Soru & Cevaplar'**
  String get allQuestionsTitle;

  /// No description provided for @errorLoadingSeller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı yüklenirken hata oluştu'**
  String get errorLoadingSeller;

  /// No description provided for @errorLoadingQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Sorular yüklenirken hata oluştu'**
  String get errorLoadingQuestions;

  /// No description provided for @missingItemsInOrder.
  ///
  /// In tr, this message translates to:
  /// **'Bu siparişte eksik ürünler vardır'**
  String get missingItemsInOrder;

  /// No description provided for @noQuestionsFound.
  ///
  /// In tr, this message translates to:
  /// **'No questions were found'**
  String get noQuestionsFound;

  /// No description provided for @kid.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk'**
  String get kid;

  /// No description provided for @productQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Soruları'**
  String get productQuestions;

  /// No description provided for @likeQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Soruyu Beğen'**
  String get likeQuestion;

  /// No description provided for @productQuestionsHeader.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Soru & Cevapları'**
  String get productQuestionsHeader;

  /// No description provided for @anonymous.
  ///
  /// In tr, this message translates to:
  /// **'Belirsiz'**
  String get anonymous;

  /// View all questions link with count
  ///
  /// In tr, this message translates to:
  /// **'Tümü ({count}) ›'**
  String viewAllQuestions(Object count);

  /// No description provided for @footwearGenderWoman.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get footwearGenderWoman;

  /// No description provided for @jumpToToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugüne atla'**
  String get jumpToToday;

  /// No description provided for @allCaughtUp.
  ///
  /// In tr, this message translates to:
  /// **'Hepsi görüldü'**
  String get allCaughtUp;

  /// No description provided for @noBoostedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarılmış ürün bulunmamaktadır'**
  String get noBoostedProducts;

  /// No description provided for @failedToLoadAds.
  ///
  /// In tr, this message translates to:
  /// **'Reklamlar yüklenirken hata oluştu'**
  String get failedToLoadAds;

  /// No description provided for @all.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get all;

  /// No description provided for @noInternet.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantınızı kontrol edip tekrar deneyiniz.'**
  String get noInternet;

  /// No description provided for @selectAtLeastOneCategory.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir kategori türü seçin'**
  String get selectAtLeastOneCategory;

  /// No description provided for @enterContactNo.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen iletişim bilgisi girin'**
  String get enterContactNo;

  /// No description provided for @enterAddress.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen işletme adres bilgisi girin'**
  String get enterAddress;

  /// No description provided for @preparingPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Hazırlanıyor'**
  String get preparingPayment;

  /// No description provided for @pleaseWait.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bekleyin'**
  String get pleaseWait;

  /// No description provided for @maximumProductsCanBeBoostedAtOnce.
  ///
  /// In tr, this message translates to:
  /// **'Aynı anda en fazla 5 ürün öne çıkarabilirsiniz'**
  String get maximumProductsCanBeBoostedAtOnce;

  /// No description provided for @yourProductsAreNowBoosted.
  ///
  /// In tr, this message translates to:
  /// **'Ürünleriniz başarıyla öne çıkarıldı'**
  String get yourProductsAreNowBoosted;

  /// No description provided for @contactNo.
  ///
  /// In tr, this message translates to:
  /// **'İletişim Bilgisi'**
  String get contactNo;

  /// No description provided for @shopAddress.
  ///
  /// In tr, this message translates to:
  /// **'İşletme adresi'**
  String get shopAddress;

  /// No description provided for @comingSoon.
  ///
  /// In tr, this message translates to:
  /// **'Pek Yakında'**
  String get comingSoon;

  /// No description provided for @food.
  ///
  /// In tr, this message translates to:
  /// **'Yemek'**
  String get food;

  /// No description provided for @boostAnalytics.
  ///
  /// In tr, this message translates to:
  /// **'Yükseltme Analitiği'**
  String get boostAnalytics;

  /// No description provided for @noBoostHistory.
  ///
  /// In tr, this message translates to:
  /// **'Yükseltme Geçmişi Yok'**
  String get noBoostHistory;

  /// No description provided for @selectAvailableSizes.
  ///
  /// In tr, this message translates to:
  /// **'Uygun Boyutları'**
  String get selectAvailableSizes;

  /// No description provided for @pleaseSelectAtLeastOneSize.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir boyut seçin'**
  String get pleaseSelectAtLeastOneSize;

  /// No description provided for @enterEmailToConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Onaylamak için e-postanızı girin'**
  String get enterEmailToConfirm;

  /// No description provided for @completedOperations.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlanan İşlemler'**
  String get completedOperations;

  /// No description provided for @gathered.
  ///
  /// In tr, this message translates to:
  /// **'Toplanan'**
  String get gathered;

  /// No description provided for @distributed.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtılan'**
  String get distributed;

  /// No description provided for @filterByDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarihe Göre Filtrele'**
  String get filterByDate;

  /// No description provided for @clearFilter.
  ///
  /// In tr, this message translates to:
  /// **'Filtreyi Temizle'**
  String get clearFilter;

  /// No description provided for @noGatheredItems.
  ///
  /// In tr, this message translates to:
  /// **'Toplanan ürün yok'**
  String get noGatheredItems;

  /// No description provided for @noDistributedOrders.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtılan sipariş yok'**
  String get noDistributedOrders;

  /// No description provided for @cancelOperation.
  ///
  /// In tr, this message translates to:
  /// **'İşlemi İptal Et'**
  String get cancelOperation;

  /// No description provided for @cancelGatheredItemMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün toplanan durumundan çıkarılıp atanmış durumuna geri dönecek. Devam edilsin mi?'**
  String get cancelGatheredItemMessage;

  /// No description provided for @cancelDistributedOrderMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu sipariş teslim edildi durumundan çıkarılıp atanmış durumuna geri dönecek. Devam edilsin mi?'**
  String get cancelDistributedOrderMessage;

  /// No description provided for @operationCanceled.
  ///
  /// In tr, this message translates to:
  /// **'İşlem başarıyla iptal edildi'**
  String get operationCanceled;

  /// No description provided for @couldntGather.
  ///
  /// In tr, this message translates to:
  /// **'Toplanamadı'**
  String get couldntGather;

  /// No description provided for @couldntDeliver.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edilemedi'**
  String get couldntDeliver;

  /// No description provided for @selectReason.
  ///
  /// In tr, this message translates to:
  /// **'Bir sebep seçin:'**
  String get selectReason;

  /// No description provided for @reasonNotResponding.
  ///
  /// In tr, this message translates to:
  /// **'Yanıt vermediler'**
  String get reasonNotResponding;

  /// No description provided for @reasonAway.
  ///
  /// In tr, this message translates to:
  /// **'Yerinde değillerdi'**
  String get reasonAway;

  /// No description provided for @reasonClosed.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan/Konum kapalıydı'**
  String get reasonClosed;

  /// No description provided for @reasonWrongAddress.
  ///
  /// In tr, this message translates to:
  /// **'Yanlış adres'**
  String get reasonWrongAddress;

  /// No description provided for @additionalNotes.
  ///
  /// In tr, this message translates to:
  /// **'Ek notlar (opsiyonel):'**
  String get additionalNotes;

  /// No description provided for @optionalNotes.
  ///
  /// In tr, this message translates to:
  /// **'Ek detaylar girebilirsiniz...'**
  String get optionalNotes;

  /// No description provided for @stopMarkedAsFailed.
  ///
  /// In tr, this message translates to:
  /// **'Durak başarısız olarak işaretlendi'**
  String get stopMarkedAsFailed;

  /// No description provided for @allStopsProcessed.
  ///
  /// In tr, this message translates to:
  /// **'Tüm duraklar işlendi'**
  String get allStopsProcessed;

  /// No description provided for @emailMismatch.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresi hesabınızla eşleşmiyor'**
  String get emailMismatch;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hesap silme işlemi başarısız. Lütfen tekrar deneyin.'**
  String get deleteAccountFailed;

  /// No description provided for @selectFootwearSize.
  ///
  /// In tr, this message translates to:
  /// **'Boyut Seçiniz'**
  String get selectFootwearSize;

  /// No description provided for @ibanOwner.
  ///
  /// In tr, this message translates to:
  /// **'IBAN Sahibi'**
  String get ibanOwner;

  /// No description provided for @selectMeasurement.
  ///
  /// In tr, this message translates to:
  /// **'Beden'**
  String get selectMeasurement;

  /// No description provided for @startTime.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç saati'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş saati'**
  String get endTime;

  /// No description provided for @footwearGenderMan.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get footwearGenderMan;

  /// No description provided for @footwearGenderKid.
  ///
  /// In tr, this message translates to:
  /// **'Kid'**
  String get footwearGenderKid;

  /// No description provided for @pleaseFillAllDetails.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen tüm alanları doldurunuz'**
  String get pleaseFillAllDetails;

  /// Message shown in the boost‑complete dialog
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla öne çıkarıldı! Detaylı bilgi için {path} ziyaret edin.'**
  String boostCompleted(Object path);

  /// The navigation path segment to analytics
  ///
  /// In tr, this message translates to:
  /// **'Profil > Boosts > Analizler'**
  String get boostPath;

  /// No description provided for @passwordHint.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi girin'**
  String get passwordHint;

  /// No description provided for @loginButton.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get loginButton;

  /// No description provided for @selectSubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Alt Kategori Seç'**
  String get selectSubcategory;

  /// No description provided for @userPermissions.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı Hakları'**
  String get userPermissions;

  /// İzinlerin yönetildiği mağazanın adı ile birlikte başlık.
  ///
  /// In tr, this message translates to:
  /// **'{shopName} için izinler yönetiliyor:'**
  String managingPermissionsFor(Object shopName);

  /// No description provided for @emailInvitee.
  ///
  /// In tr, this message translates to:
  /// **'Davetlinin e-posta adresi'**
  String get emailInvitee;

  /// No description provided for @role.
  ///
  /// In tr, this message translates to:
  /// **'Rol'**
  String get role;

  /// No description provided for @sendInvitation.
  ///
  /// In tr, this message translates to:
  /// **'Davet gönder'**
  String get sendInvitation;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir e-posta adresi girin.'**
  String get pleaseEnterValidEmail;

  /// No description provided for @userNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta adresine sahip kullanıcı bulunamadı'**
  String get userNotFound;

  /// No description provided for @rolePermissions.
  ///
  /// In tr, this message translates to:
  /// **'Rol İzinleri:'**
  String get rolePermissions;

  /// No description provided for @rolePermissionsDetail.
  ///
  /// In tr, this message translates to:
  /// **'Sahibi: Tam erişim\nEditör: Ürün yönetimi yapabilir\nGörüntüleyici: Yalnızca okuma izni'**
  String get rolePermissionsDetail;

  /// No description provided for @pendingInvitations.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen Davetler:'**
  String get pendingInvitations;

  /// No description provided for @noPendingInvitations.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen davet yok.'**
  String get noPendingInvitations;

  /// Bekleyen davet listesindeki davetlinin e-posta etiket mesajı.
  ///
  /// In tr, this message translates to:
  /// **'Davetlinin E-posta: {email}'**
  String inviteeEmail(Object email);

  /// No description provided for @invitationCancelled.
  ///
  /// In tr, this message translates to:
  /// **'Davet iptal edildi.'**
  String get invitationCancelled;

  /// Davet iptalinde hata mesajı.
  ///
  /// In tr, this message translates to:
  /// **'Davet iptal edilirken hata oluştu: {error}'**
  String errorCancellingInvitation(Object error);

  /// No description provided for @acceptedUsers.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Edilen Kullanıcılar:'**
  String get acceptedUsers;

  /// No description provided for @noAcceptedUsers.
  ///
  /// In tr, this message translates to:
  /// **'Kabul edilen kullanıcı yok.'**
  String get noAcceptedUsers;

  /// Kullanıcının rolünü belirten etiket.
  ///
  /// In tr, this message translates to:
  /// **'Rol: {role}'**
  String roleLabel(Object role);

  /// No description provided for @roleCoOwner.
  ///
  /// In tr, this message translates to:
  /// **'Eş-sahip'**
  String get roleCoOwner;

  /// No description provided for @roleEditor.
  ///
  /// In tr, this message translates to:
  /// **'Editör'**
  String get roleEditor;

  /// No description provided for @roleViewer.
  ///
  /// In tr, this message translates to:
  /// **'Görüntüleyici'**
  String get roleViewer;

  /// No description provided for @roleOwner.
  ///
  /// In tr, this message translates to:
  /// **'Sahibi'**
  String get roleOwner;

  /// Davet gönderilemediğinde hata mesajı.
  ///
  /// In tr, this message translates to:
  /// **'Davet gönderilemedi: {error}'**
  String errorSendingInvitation(Object error);

  /// Erişim kaldırma hatası mesajı.
  ///
  /// In tr, this message translates to:
  /// **'Erişim kaldırılırken hata oluştu: {error}'**
  String errorRevokingAccess(Object error);

  /// No description provided for @noShopSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçili mağaza yok'**
  String get noShopSelected;

  /// No description provided for @selectCondition.
  ///
  /// In tr, this message translates to:
  /// **'Ürün durumu seçin'**
  String get selectCondition;

  /// No description provided for @clothingGenderWoman.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get clothingGenderWoman;

  /// No description provided for @listCar.
  ///
  /// In tr, this message translates to:
  /// **'Araç listele'**
  String get listCar;

  /// No description provided for @saleType.
  ///
  /// In tr, this message translates to:
  /// **'Satış Türü'**
  String get saleType;

  /// No description provided for @saleTypePlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Satış Türü'**
  String get saleTypePlaceholder;

  /// Arama sonuçları
  ///
  /// In tr, this message translates to:
  /// **'\"{query}\" için arama sonuçları'**
  String searchResultsFor(Object query);

  /// No description provided for @adManagement.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Yönetimi'**
  String get adManagement;

  /// No description provided for @createAd.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Oluştur'**
  String get createAd;

  /// No description provided for @myAds.
  ///
  /// In tr, this message translates to:
  /// **'Reklamlarım'**
  String get myAds;

  /// No description provided for @adSubmissionInfo.
  ///
  /// In tr, this message translates to:
  /// **'Reklamınızı inceleme için gönderin. Onaylandığında ödeme linki alacaksınız. Ödeme sonrası reklamınız yayına girecek.'**
  String get adSubmissionInfo;

  /// No description provided for @selectAdType.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Tipi Seçin'**
  String get selectAdType;

  /// No description provided for @topBanner.
  ///
  /// In tr, this message translates to:
  /// **'Üst Banner'**
  String get topBanner;

  /// No description provided for @topBannerDescription.
  ///
  /// In tr, this message translates to:
  /// **'Market ekranının en üstünde görünür, baskın renk çıkarımı yapılır'**
  String get topBannerDescription;

  /// No description provided for @thinBanner.
  ///
  /// In tr, this message translates to:
  /// **'İnce Banner'**
  String get thinBanner;

  /// No description provided for @bannerDimensions.
  ///
  /// In tr, this message translates to:
  /// **'Görseller yatay olmalıdır'**
  String get bannerDimensions;

  /// No description provided for @thinBannerDescription.
  ///
  /// In tr, this message translates to:
  /// **'Üst banner\'ın altında yatay olarak görüntülenen ince banner'**
  String get thinBannerDescription;

  /// No description provided for @marketBanner.
  ///
  /// In tr, this message translates to:
  /// **'Market Banner'**
  String get marketBanner;

  /// No description provided for @marketBannerDescription.
  ///
  /// In tr, this message translates to:
  /// **'Market grid bölümünde görüntülenen kare formatında bannerlar'**
  String get marketBannerDescription;

  /// No description provided for @adSubmittedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Reklam başarıyla gönderildi! Admin incelemesini bekleyin.'**
  String get adSubmittedSuccessfully;

  /// No description provided for @errorUploadingAd.
  ///
  /// In tr, this message translates to:
  /// **'Reklam yüklenirken hata oluştu. Lütfen tekrar deneyin.'**
  String get errorUploadingAd;

  /// No description provided for @noAdsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz Reklam Yok'**
  String get noAdsYet;

  /// No description provided for @submitYourFirstAd.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızı tanıtmak için ilk reklamınızı gönderin'**
  String get submitYourFirstAd;

  /// No description provided for @pending.
  ///
  /// In tr, this message translates to:
  /// **'Beklemede'**
  String get pending;

  /// No description provided for @approved.
  ///
  /// In tr, this message translates to:
  /// **'Onaylandı'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In tr, this message translates to:
  /// **'Reddedildi'**
  String get rejected;

  /// No description provided for @paid.
  ///
  /// In tr, this message translates to:
  /// **'Ödendi'**
  String get paid;

  /// No description provided for @active.
  ///
  /// In tr, this message translates to:
  /// **'Aktif'**
  String get active;

  /// No description provided for @proceedToPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeyi tamamla'**
  String get proceedToPayment;

  /// No description provided for @today.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In tr, this message translates to:
  /// **'Dün'**
  String get yesterday;

  /// No description provided for @daysAgoText.
  ///
  /// In tr, this message translates to:
  /// **'gün önce'**
  String get daysAgoText;

  /// No description provided for @paymentSummary.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Özeti'**
  String get paymentSummary;

  /// No description provided for @adPayment.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Ödemesi'**
  String get adPayment;

  /// No description provided for @adPreview.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Önizleme'**
  String get adPreview;

  /// No description provided for @adType.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Tipi'**
  String get adType;

  /// No description provided for @duration.
  ///
  /// In tr, this message translates to:
  /// **'Süre'**
  String get duration;

  /// No description provided for @shop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan'**
  String get shop;

  /// No description provided for @priceBreakdown.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Dökümü'**
  String get priceBreakdown;

  /// No description provided for @adCost.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Ücreti'**
  String get adCost;

  /// No description provided for @tax.
  ///
  /// In tr, this message translates to:
  /// **'KDV (%20)'**
  String get tax;

  /// No description provided for @totalAmount.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Tutar'**
  String get totalAmount;

  /// No description provided for @acceptTermsAndConditions.
  ///
  /// In tr, this message translates to:
  /// **'Reklam yerleştirme ve ödeme için şartları ve koşulları kabul ediyorum'**
  String get acceptTermsAndConditions;

  /// No description provided for @continueToPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeye Devam'**
  String get continueToPayment;

  /// No description provided for @pleaseAcceptTerms.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için kullanım koşullarını kabul etmelisiniz'**
  String get pleaseAcceptTerms;

  /// No description provided for @paymentTimeout.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Zaman Aşımı'**
  String get paymentTimeout;

  /// No description provided for @paymentTimeoutMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme oturumu sona erdi. Lütfen tekrar deneyin.'**
  String get paymentTimeoutMessage;

  /// No description provided for @homeScreenAds.
  ///
  /// In tr, this message translates to:
  /// **'Ana Sayfa Reklamları'**
  String get homeScreenAds;

  /// No description provided for @adApproved.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Onaylandı'**
  String get adApproved;

  /// No description provided for @paymentInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme bilgisi bulunamadı'**
  String get paymentInfoNotFound;

  /// No description provided for @uploadingAd.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Yükleniyor'**
  String get uploadingAd;

  /// No description provided for @preparingImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel hazırlanıyor...'**
  String get preparingImage;

  /// No description provided for @uploadingImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel yükleniyor...'**
  String get uploadingImage;

  /// No description provided for @savingAdData.
  ///
  /// In tr, this message translates to:
  /// **'Reklam kaydediliyor...'**
  String get savingAdData;

  /// No description provided for @complete.
  ///
  /// In tr, this message translates to:
  /// **'Tamamla'**
  String get complete;

  /// No description provided for @adUnderReview.
  ///
  /// In tr, this message translates to:
  /// **'Reklamınız inceleme altında'**
  String get adUnderReview;

  /// No description provided for @imageTooLarge.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum dosya boyutu 10 MB olmalıdır.'**
  String get imageTooLarge;

  /// No description provided for @adPaymentSuccessMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeniz başarıyla tamamlandı! Reklamınız kısa süre içinde aktif edilecek.'**
  String get adPaymentSuccessMessage;

  /// No description provided for @gotIt.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get gotIt;

  /// No description provided for @initializingPayment.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli ödeme başlatılıyor...'**
  String get initializingPayment;

  /// No description provided for @selectDuration.
  ///
  /// In tr, this message translates to:
  /// **'Süre Seçin'**
  String get selectDuration;

  /// No description provided for @oneWeek.
  ///
  /// In tr, this message translates to:
  /// **'1 Hafta'**
  String get oneWeek;

  /// No description provided for @twoWeeks.
  ///
  /// In tr, this message translates to:
  /// **'2 Hafta'**
  String get twoWeeks;

  /// No description provided for @oneMonth.
  ///
  /// In tr, this message translates to:
  /// **'1 Ay'**
  String get oneMonth;

  /// No description provided for @oneWeekShort.
  ///
  /// In tr, this message translates to:
  /// **'1 Hafta'**
  String get oneWeekShort;

  /// No description provided for @inCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepette'**
  String get inCart;

  /// No description provided for @twoWeeksShort.
  ///
  /// In tr, this message translates to:
  /// **'2 Hafta'**
  String get twoWeeksShort;

  /// No description provided for @oneMonthShort.
  ///
  /// In tr, this message translates to:
  /// **'1 Ay'**
  String get oneMonthShort;

  /// No description provided for @recommended.
  ///
  /// In tr, this message translates to:
  /// **'Tavsiye edilen'**
  String get recommended;

  /// No description provided for @bestValue.
  ///
  /// In tr, this message translates to:
  /// **'En İyi Değer'**
  String get bestValue;

  /// No description provided for @continueText.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get continueText;

  /// No description provided for @forSale.
  ///
  /// In tr, this message translates to:
  /// **'Satılık'**
  String get forSale;

  /// No description provided for @forRent.
  ///
  /// In tr, this message translates to:
  /// **'Kiralık'**
  String get forRent;

  /// No description provided for @sizeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Beden'**
  String get sizeLabel;

  /// No description provided for @carType.
  ///
  /// In tr, this message translates to:
  /// **'Araç Tipi'**
  String get carType;

  /// No description provided for @followers.
  ///
  /// In tr, this message translates to:
  /// **'Takipçiler'**
  String get followers;

  /// No description provided for @selectOptions.
  ///
  /// In tr, this message translates to:
  /// **'Seçeneklerden Seç'**
  String get selectOptions;

  /// No description provided for @createCampaing.
  ///
  /// In tr, this message translates to:
  /// **'Kampanya yarat'**
  String get createCampaing;

  /// No description provided for @buyTogetherAndSave.
  ///
  /// In tr, this message translates to:
  /// **'Birlikte Al & Tasarruf Et'**
  String get buyTogetherAndSave;

  /// No description provided for @specialBundleOffersWithThisProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünle özel paket teklifleri'**
  String get specialBundleOffersWithThisProduct;

  /// Text showing how much money user can save in bundle
  ///
  /// In tr, this message translates to:
  /// **'{amount} {currency} tasarruf et'**
  String saveAmount(String amount, String currency);

  /// No description provided for @productNotAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Ürün artık mevcut değil'**
  String get productNotAvailable;

  /// Error message when navigation fails
  ///
  /// In tr, this message translates to:
  /// **'Gezinme hatası: {error}'**
  String navigationError(String error);

  /// No description provided for @productBundles.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Paketleri'**
  String get productBundles;

  /// No description provided for @selectProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bir ürün seçin'**
  String get selectProduct;

  /// No description provided for @activeBundlesCount.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Paketler ({count})'**
  String activeBundlesCount(Object count);

  /// No description provided for @searchProducts.
  ///
  /// In tr, this message translates to:
  /// **'Marka, ürün veya kategori ara'**
  String get searchProducts;

  /// No description provided for @noHomeContent.
  ///
  /// In tr, this message translates to:
  /// **'Ana sayfa içeriği bulunmuyor'**
  String get noHomeContent;

  /// No description provided for @noCollections.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon bulunmuyor'**
  String get noCollections;

  /// No description provided for @shipmentPending.
  ///
  /// In tr, this message translates to:
  /// **'Bekliyor'**
  String get shipmentPending;

  /// No description provided for @shipmentCollecting.
  ///
  /// In tr, this message translates to:
  /// **'Toplanıyor'**
  String get shipmentCollecting;

  /// No description provided for @shipmentInTransit.
  ///
  /// In tr, this message translates to:
  /// **'Yolda'**
  String get shipmentInTransit;

  /// No description provided for @shipmentAtWarehouse.
  ///
  /// In tr, this message translates to:
  /// **'Depoda'**
  String get shipmentAtWarehouse;

  /// No description provided for @shipmentOutForDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtımda'**
  String get shipmentOutForDelivery;

  /// No description provided for @shipmentDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edildi'**
  String get shipmentDelivered;

  /// No description provided for @shipmentFailed.
  ///
  /// In tr, this message translates to:
  /// **'Başarısız'**
  String get shipmentFailed;

  /// No description provided for @shipmentInProgress.
  ///
  /// In tr, this message translates to:
  /// **'İşlemde'**
  String get shipmentInProgress;

  /// No description provided for @noPendingShipments.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen gönderi yok'**
  String get noPendingShipments;

  /// No description provided for @noInProgressShipments.
  ///
  /// In tr, this message translates to:
  /// **'İşlemde gönderi yok'**
  String get noInProgressShipments;

  /// No description provided for @noDeliveredShipments.
  ///
  /// In tr, this message translates to:
  /// **'Teslim edilen gönderi yok'**
  String get noDeliveredShipments;

  /// No description provided for @noProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürün yok'**
  String get noProducts;

  /// No description provided for @addProductsToCreateBundles.
  ///
  /// In tr, this message translates to:
  /// **'Paket oluşturmak için ürün ekleyin'**
  String get addProductsToCreateBundles;

  /// No description provided for @noActiveBundles.
  ///
  /// In tr, this message translates to:
  /// **'Aktif Paket Yok'**
  String get noActiveBundles;

  /// No description provided for @createProductBundlesToOfferSpecialPrices.
  ///
  /// In tr, this message translates to:
  /// **'Özel fiyatlar sunmak için ürün paketleri oluşturun'**
  String get createProductBundlesToOfferSpecialPrices;

  /// No description provided for @complementaryProductsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} tamamlayıcı ürün'**
  String complementaryProductsCount(Object count);

  /// No description provided for @moreProductsCount.
  ///
  /// In tr, this message translates to:
  /// **'+{count} tane daha'**
  String moreProductsCount(int count);

  /// No description provided for @editBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paketi Düzenle'**
  String get editBundle;

  /// No description provided for @deleteBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paketi Sil'**
  String get deleteBundle;

  /// No description provided for @deleteBundleConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu paketi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'**
  String get deleteBundleConfirmation;

  /// No description provided for @bundleDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Paket başarıyla silindi!'**
  String get bundleDeletedSuccessfully;

  /// No description provided for @bundleUpdatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Paket başarıyla güncellendi!'**
  String get bundleUpdatedSuccessfully;

  /// No description provided for @failedToDeleteBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket silinemedi: {error}'**
  String failedToDeleteBundle(String error);

  /// No description provided for @failedToUpdateBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket güncellenemedi: {error}'**
  String failedToUpdateBundle(String error);

  /// No description provided for @securePayment.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli Ödeme'**
  String get securePayment;

  /// No description provided for @paymentError.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Hatası'**
  String get paymentError;

  /// No description provided for @cancelPaymentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeyi İptal Et?'**
  String get cancelPaymentTitle;

  /// No description provided for @cancelPaymentMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme işlemini iptal etmek istediğinize emin misiniz?'**
  String get cancelPaymentMessage;

  /// No description provided for @loadingPaymentPage.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme sayfası yükleniyor...'**
  String get loadingPaymentPage;

  /// No description provided for @connectionError.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı hatası. Lütfen internet bağlantınızı kontrol edin.'**
  String get connectionError;

  /// No description provided for @ok.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get ok;

  /// No description provided for @mainProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ana Ürün'**
  String get mainProduct;

  /// No description provided for @currentItemsCount.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Öğeler ({count})'**
  String currentItemsCount(Object count);

  /// No description provided for @cargoPrice.
  ///
  /// In tr, this message translates to:
  /// **'Kargo Ücreti'**
  String get cargoPrice;

  /// No description provided for @noBundleItems.
  ///
  /// In tr, this message translates to:
  /// **'Paket Öğesi Yok'**
  String get noBundleItems;

  /// No description provided for @addProductsToThisBundle.
  ///
  /// In tr, this message translates to:
  /// **'Bu pakete ürün ekleyin'**
  String get addProductsToThisBundle;

  /// No description provided for @productCurrentlyUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda mevcut değil'**
  String get productCurrentlyUnavailable;

  /// No description provided for @insufficientStock.
  ///
  /// In tr, this message translates to:
  /// **'Sadece {available} adet mevcut ({requested} adet istediniz)'**
  String insufficientStock(int available, int requested);

  /// No description provided for @maxQuantityExceeded.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum izin verilen: {max}'**
  String maxQuantityExceeded(int max);

  /// No description provided for @priceChanged.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat değişti: {currency} {oldPrice} → {newPrice}'**
  String priceChanged(String currency, String oldPrice, String newPrice);

  /// No description provided for @bundlePriceChanged.
  ///
  /// In tr, this message translates to:
  /// **'Paket fiyatı değişti: {currency} {oldPrice} → {newPrice}'**
  String bundlePriceChanged(String currency, String oldPrice, String newPrice);

  /// No description provided for @discountUpdated.
  ///
  /// In tr, this message translates to:
  /// **'İndirim güncellendi: %{oldDiscount} → %{newDiscount}'**
  String discountUpdated(int oldDiscount, int newDiscount);

  /// No description provided for @discountThresholdChanged.
  ///
  /// In tr, this message translates to:
  /// **'Toplu indirim eşiği değişti: {oldThreshold}+ al → {newThreshold}+ al'**
  String discountThresholdChanged(int oldThreshold, int newThreshold);

  /// No description provided for @maxQuantityReduced.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum miktar azaldı: {oldMax} → {newMax}'**
  String maxQuantityReduced(int oldMax, int newMax);

  /// No description provided for @price.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat'**
  String get price;

  /// No description provided for @bundlePrice.
  ///
  /// In tr, this message translates to:
  /// **'Paket Fiyatı'**
  String get bundlePrice;

  /// No description provided for @discountThreshold.
  ///
  /// In tr, this message translates to:
  /// **'Toplu İndirim'**
  String get discountThreshold;

  /// No description provided for @maxQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Maks. Miktar'**
  String get maxQuantity;

  /// No description provided for @buy.
  ///
  /// In tr, this message translates to:
  /// **'Al'**
  String get buy;

  /// No description provided for @color.
  ///
  /// In tr, this message translates to:
  /// **'Renk'**
  String get color;

  /// No description provided for @validationIssuesDetected.
  ///
  /// In tr, this message translates to:
  /// **'Değişiklikler Tespit Edildi'**
  String get validationIssuesDetected;

  /// No description provided for @validationErrorsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Devam Edilemiyor'**
  String get validationErrorsTitle;

  /// No description provided for @validationWarningsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Değişiklikleri Tespit Edildi'**
  String get validationWarningsTitle;

  /// No description provided for @validationBothIssues.
  ///
  /// In tr, this message translates to:
  /// **'{errors} engelleyici sorun, {warnings} uyarı'**
  String validationBothIssues(int errors, int warnings);

  /// No description provided for @validationErrorsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} ürün mevcut değil'**
  String validationErrorsCount(int count);

  /// No description provided for @validationWarningsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} üründe değişiklik var'**
  String validationWarningsCount(int count);

  /// No description provided for @reservationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Stok rezervasyonu başarısız. Lütfen tekrar deneyin.'**
  String get reservationFailed;

  /// No description provided for @validationWillBeRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün siparişinizden kaldırılacak'**
  String get validationWillBeRemoved;

  /// No description provided for @validationAcceptChange.
  ///
  /// In tr, this message translates to:
  /// **'Bu değişikliği kabul ediyorum'**
  String get validationAcceptChange;

  /// No description provided for @validationContinueWithoutErrors.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Olmayan Ürünler Olmadan Devam Et'**
  String get validationContinueWithoutErrors;

  /// No description provided for @validationContinueWithChanges.
  ///
  /// In tr, this message translates to:
  /// **'Değişikliklerle Devam Et'**
  String get validationContinueWithChanges;

  /// No description provided for @originalPrice.
  ///
  /// In tr, this message translates to:
  /// **'Orijinal: {price}'**
  String originalPrice(Object price);

  /// No description provided for @deletingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün siliniyor...'**
  String get deletingProduct;

  /// No description provided for @deleteProductConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz. Ürün kalıcı olarak silinecektir.'**
  String get deleteProductConfirmation;

  /// No description provided for @deleteProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü Sil'**
  String get deleteProduct;

  /// No description provided for @productDeleteError.
  ///
  /// In tr, this message translates to:
  /// **'Ürün silinemedi. Lütfen tekrar deneyin.'**
  String get productDeleteError;

  /// No description provided for @productDeletedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla silindi'**
  String get productDeletedSuccess;

  /// No description provided for @joiningShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan paneli yükleniyor...'**
  String get joiningShop;

  /// No description provided for @revokeAccess.
  ///
  /// In tr, this message translates to:
  /// **'Erişimi İptal Et'**
  String get revokeAccess;

  /// No description provided for @revokeAccessConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcının mağazaya erişimi kaldırılacak.'**
  String get revokeAccessConfirmation;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz. Tüm verileriniz kalıcı olarak silinecektir.'**
  String get deleteAccountWarning;

  /// No description provided for @deletingAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap siliniyor...'**
  String get deletingAccount;

  /// No description provided for @deletingAccountDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınız ve tüm ilişkili verileriniz silinirken lütfen bekleyin.'**
  String get deletingAccountDesc;

  /// No description provided for @cargoPanel.
  ///
  /// In tr, this message translates to:
  /// **'Kargo Paneli'**
  String get cargoPanel;

  /// No description provided for @toGather.
  ///
  /// In tr, this message translates to:
  /// **'Toplanacak'**
  String get toGather;

  /// No description provided for @toDistribute.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtılacak'**
  String get toDistribute;

  /// No description provided for @noOrdersAssigned.
  ///
  /// In tr, this message translates to:
  /// **'Henüz atanmış sipariş yok'**
  String get noOrdersAssigned;

  /// No description provided for @createRoute.
  ///
  /// In tr, this message translates to:
  /// **'Rota Oluştur'**
  String get createRoute;

  /// No description provided for @deliveryAddress.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Adresi'**
  String get deliveryAddress;

  /// No description provided for @orderItems.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Ürünleri'**
  String get orderItems;

  /// No description provided for @deliveryType.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Tipi'**
  String get deliveryType;

  /// No description provided for @normalDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Normal Teslimat'**
  String get normalDelivery;

  /// No description provided for @expressDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Teslimat'**
  String get expressDelivery;

  /// No description provided for @gelalDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Gelal Teslimat'**
  String get gelalDelivery;

  /// No description provided for @pickupDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Alma'**
  String get pickupDelivery;

  /// No description provided for @markAsGathered.
  ///
  /// In tr, this message translates to:
  /// **'Toplandı Olarak İşaretle'**
  String get markAsGathered;

  /// No description provided for @markAsDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edildi Olarak İşaretle'**
  String get markAsDelivered;

  /// No description provided for @markedAsGathered.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş başarıyla toplandı olarak işaretlendi'**
  String get markedAsGathered;

  /// No description provided for @markedAsDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş başarıyla teslim edildi olarak işaretlendi'**
  String get markedAsDelivered;

  /// No description provided for @confirmAction.
  ///
  /// In tr, this message translates to:
  /// **'İşlemi Onayla'**
  String get confirmAction;

  /// No description provided for @confirmGathered.
  ///
  /// In tr, this message translates to:
  /// **'Bu siparişi toplandı olarak işaretlemek istediğinizden emin misiniz?'**
  String get confirmGathered;

  /// No description provided for @confirmDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Teslimatı Onayla'**
  String get confirmDelivered;

  /// No description provided for @confirm.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get confirm;

  /// No description provided for @seller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı'**
  String get seller;

  /// No description provided for @optimizedRoute.
  ///
  /// In tr, this message translates to:
  /// **'Optimize Edilmiş Rota'**
  String get optimizedRoute;

  /// No description provided for @openInMaps.
  ///
  /// In tr, this message translates to:
  /// **'Haritalarda Aç'**
  String get openInMaps;

  /// No description provided for @cannotOpenMaps.
  ///
  /// In tr, this message translates to:
  /// **'Haritalar açılamıyor'**
  String get cannotOpenMaps;

  /// No description provided for @totalStops.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Durak'**
  String get totalStops;

  /// No description provided for @stops.
  ///
  /// In tr, this message translates to:
  /// **'durak'**
  String get stops;

  /// No description provided for @current.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut'**
  String get current;

  /// No description provided for @previous.
  ///
  /// In tr, this message translates to:
  /// **'Önceki'**
  String get previous;

  /// No description provided for @nextStop.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki Durak'**
  String get nextStop;

  /// No description provided for @moreItems.
  ///
  /// In tr, this message translates to:
  /// **'ürün daha'**
  String get moreItems;

  /// No description provided for @gathering.
  ///
  /// In tr, this message translates to:
  /// **'Toplama'**
  String get gathering;

  /// No description provided for @distribution.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtım'**
  String get distribution;

  /// No description provided for @noItemsAssigned.
  ///
  /// In tr, this message translates to:
  /// **'Henüz atanmış ürün yok'**
  String get noItemsAssigned;

  /// No description provided for @itemMarkedAsGathered.
  ///
  /// In tr, this message translates to:
  /// **'Ürün toplandı olarak işaretlendi'**
  String get itemMarkedAsGathered;

  /// No description provided for @itemMarkedAsArrived.
  ///
  /// In tr, this message translates to:
  /// **'Ürün depoya geldi olarak işaretlendi'**
  String get itemMarkedAsArrived;

  /// No description provided for @markAsArrived.
  ///
  /// In tr, this message translates to:
  /// **'Depoya Geldi'**
  String get markAsArrived;

  /// No description provided for @itemsToGather.
  ///
  /// In tr, this message translates to:
  /// **'Toplanacak Ürünler'**
  String get itemsToGather;

  /// No description provided for @ordersToDeliver.
  ///
  /// In tr, this message translates to:
  /// **'Teslim Edilecek Siparişler'**
  String get ordersToDeliver;

  /// No description provided for @pendingProductApplications.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Başvuruları'**
  String get pendingProductApplications;

  /// No description provided for @noApplicationsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru Yok'**
  String get noApplicationsTitle;

  /// No description provided for @noApplicationsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ürün başvurusu yapmadınız.'**
  String get noApplicationsDescription;

  /// No description provided for @noPendingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen Başvuru Yok'**
  String get noPendingTitle;

  /// No description provided for @noPendingDescription.
  ///
  /// In tr, this message translates to:
  /// **'İncelemeyi bekleyen başvurunuz bulunmuyor.'**
  String get noPendingDescription;

  /// No description provided for @noApprovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Onaylanmış Başvuru Yok'**
  String get noApprovedTitle;

  /// No description provided for @noApprovedDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz onaylanmış başvurunuz bulunmuyor.'**
  String get noApprovedDescription;

  /// No description provided for @noRejectedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Reddedilmiş Başvuru Yok'**
  String get noRejectedTitle;

  /// No description provided for @noRejectedDescription.
  ///
  /// In tr, this message translates to:
  /// **'Reddedilmiş başvurunuz bulunmuyor.'**
  String get noRejectedDescription;

  /// No description provided for @loadMore.
  ///
  /// In tr, this message translates to:
  /// **'Daha Fazla Yükle'**
  String get loadMore;

  /// No description provided for @showingResults.
  ///
  /// In tr, this message translates to:
  /// **'{total} sonuçtan {count} tanesi gösteriliyor'**
  String showingResults(Object count, Object total);

  /// No description provided for @edit.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get edit;

  /// No description provided for @editApplication.
  ///
  /// In tr, this message translates to:
  /// **'Düzenleme Başvurusu'**
  String get editApplication;

  /// No description provided for @images.
  ///
  /// In tr, this message translates to:
  /// **'Görseller'**
  String get images;

  /// No description provided for @description.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get description;

  /// No description provided for @category.
  ///
  /// In tr, this message translates to:
  /// **'Kategori'**
  String get category;

  /// No description provided for @condition.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get condition;

  /// No description provided for @quantity.
  ///
  /// In tr, this message translates to:
  /// **'Miktar'**
  String get quantity;

  /// No description provided for @brand.
  ///
  /// In tr, this message translates to:
  /// **'Marka'**
  String get brand;

  /// No description provided for @gender.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet'**
  String get gender;

  /// No description provided for @delivery.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat'**
  String get delivery;

  /// No description provided for @colors.
  ///
  /// In tr, this message translates to:
  /// **'Renkler'**
  String get colors;

  /// No description provided for @editedFields.
  ///
  /// In tr, this message translates to:
  /// **'Düzenlenen Alanlar'**
  String get editedFields;

  /// No description provided for @submittedAt.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilme tarihi'**
  String get submittedAt;

  /// No description provided for @reviewedAt.
  ///
  /// In tr, this message translates to:
  /// **'İncelenme tarihi'**
  String get reviewedAt;

  /// No description provided for @close.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get close;

  /// No description provided for @for_.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı'**
  String get for_;

  /// No description provided for @markOrderAsDelivered.
  ///
  /// In tr, this message translates to:
  /// **'Bu siparişi teslim edildi olarak işaretle'**
  String get markOrderAsDelivered;

  /// No description provided for @pinLocationOnMap.
  ///
  /// In tr, this message translates to:
  /// **'Konumunuzu haritada işaretleyin'**
  String get pinLocationOnMap;

  /// No description provided for @toOptimizeOrderDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş teslimatlarını optimize etmek için'**
  String get toOptimizeOrderDelivery;

  /// No description provided for @locationNotSelected.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen mağazanızın konumunu haritada seçin'**
  String get locationNotSelected;

  /// No description provided for @revoke.
  ///
  /// In tr, this message translates to:
  /// **'İptal Et'**
  String get revoke;

  /// No description provided for @revokingAccess.
  ///
  /// In tr, this message translates to:
  /// **'Erişim iptal ediliyor...'**
  String get revokingAccess;

  /// No description provided for @confirmLogout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkışını Onayla'**
  String get confirmLogout;

  /// No description provided for @logoutMessage.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yapmak istediğinizden emin misiniz?'**
  String get logoutMessage;

  /// No description provided for @yourLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konumunuz'**
  String get yourLocation;

  /// No description provided for @currentPosition.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut konum'**
  String get currentPosition;

  /// No description provided for @stop.
  ///
  /// In tr, this message translates to:
  /// **'Durak'**
  String get stop;

  /// No description provided for @notAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Değil'**
  String get notAvailable;

  /// No description provided for @metersAway.
  ///
  /// In tr, this message translates to:
  /// **'m uzaklıkta'**
  String get metersAway;

  /// No description provided for @kilometersAway.
  ///
  /// In tr, this message translates to:
  /// **'km uzaklıkta'**
  String get kilometersAway;

  /// No description provided for @start.
  ///
  /// In tr, this message translates to:
  /// **'Başlat'**
  String get start;

  /// No description provided for @confirmArrival.
  ///
  /// In tr, this message translates to:
  /// **'Varışı Onayla'**
  String get confirmArrival;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In tr, this message translates to:
  /// **'Konum izinleri reddedildi'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionPermanentlyDenied.
  ///
  /// In tr, this message translates to:
  /// **'Konum izinleri kalıcı olarak reddedildi'**
  String get locationPermissionPermanentlyDenied;

  /// No description provided for @errorTrackingLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konum takip hatası'**
  String get errorTrackingLocation;

  /// No description provided for @errorLoadingDirections.
  ///
  /// In tr, this message translates to:
  /// **'Yol tarifi yükleme hatası'**
  String get errorLoadingDirections;

  /// No description provided for @waitingForLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konum bekleniyor...'**
  String get waitingForLocation;

  /// No description provided for @allStopsCompleted.
  ///
  /// In tr, this message translates to:
  /// **'Tüm duraklar tamamlandı! Gösterge paneline dönülüyor...'**
  String get allStopsCompleted;

  /// No description provided for @loadingDirections.
  ///
  /// In tr, this message translates to:
  /// **'Yol tarifi yükleniyor...'**
  String get loadingDirections;

  /// No description provided for @allProductsAlreadyInBundle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm ürünler zaten pakette'**
  String get allProductsAlreadyInBundle;

  /// No description provided for @newProductsToAdd.
  ///
  /// In tr, this message translates to:
  /// **'{count} yeni ürün eklenecek'**
  String newProductsToAdd(int count);

  /// No description provided for @saveChanges.
  ///
  /// In tr, this message translates to:
  /// **'Değişiklikleri Kaydet'**
  String get saveChanges;

  /// No description provided for @createBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket Yarat'**
  String get createBundle;

  /// No description provided for @searchComplementaryProducts.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlayıcı ürünler ara...'**
  String get searchComplementaryProducts;

  /// No description provided for @bundlePriceWithMainProduct.
  ///
  /// In tr, this message translates to:
  /// **'Paket Fiyatı (ana ürünle birlikte)'**
  String get bundlePriceWithMainProduct;

  /// No description provided for @totalPrice.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Fiyat: {totalPrice} TL'**
  String totalPrice(Object totalPrice);

  /// No description provided for @createBundlesCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} Paket Oluştur'**
  String createBundlesCount(num count);

  /// No description provided for @pleaseSelectAtLeastOneProduct.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir tamamlayıcı ürün seçin'**
  String get pleaseSelectAtLeastOneProduct;

  /// No description provided for @pleaseEnterValidPrices.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen tüm paketler için geçerli fiyatlar girin'**
  String get pleaseEnterValidPrices;

  /// No description provided for @bundleCreatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Paket başarıyla oluşturuldu!'**
  String get bundleCreatedSuccessfully;

  /// No description provided for @failedToCreateBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket oluşturulurken hata: {error}'**
  String failedToCreateBundle(Object error);

  /// No description provided for @noComplementaryProductsFound.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlayıcı ürün bulunamadı'**
  String get noComplementaryProductsFound;

  /// No description provided for @categoryBasedDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Kategori bazlı indirim'**
  String get categoryBasedDiscount;

  /// No description provided for @invalidDiscountRange.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz indirim değeri'**
  String get invalidDiscountRange;

  /// No description provided for @noProductsOnVitrin.
  ///
  /// In tr, this message translates to:
  /// **'Vitrin\'de herhangi bir ürününüz bulunmamaktadır'**
  String get noProductsOnVitrin;

  /// No description provided for @pleaseEnterQuantityForAllColors.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen tüm seçili renkler için miktar girin'**
  String get pleaseEnterQuantityForAllColors;

  /// No description provided for @salePreferences.
  ///
  /// In tr, this message translates to:
  /// **'Satış Tercihleri'**
  String get salePreferences;

  /// No description provided for @salePreferenceMaxQuantityPre.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü en fazla '**
  String get salePreferenceMaxQuantityPre;

  /// No description provided for @salePreferenceMaxQuantityPost.
  ///
  /// In tr, this message translates to:
  /// **' adet satın alabilirsiniz.'**
  String get salePreferenceMaxQuantityPost;

  /// No description provided for @salePreferenceDiscountPre.
  ///
  /// In tr, this message translates to:
  /// **'Eğer bu üründen '**
  String get salePreferenceDiscountPre;

  /// No description provided for @salePreferenceDiscountMid.
  ///
  /// In tr, this message translates to:
  /// **' adet alırsanız, toplam fiyat '**
  String get salePreferenceDiscountMid;

  /// No description provided for @salePreferenceDiscountPost.
  ///
  /// In tr, this message translates to:
  /// **' % düşecektir.'**
  String get salePreferenceDiscountPost;

  /// No description provided for @savePreferencesButtonLabel.
  ///
  /// In tr, this message translates to:
  /// **'Tercihleri Kaydet'**
  String get savePreferencesButtonLabel;

  /// No description provided for @discountThresholdExceedsMax.
  ///
  /// In tr, this message translates to:
  /// **'İndirim için gerekli miktar, maksimum miktarı aşamaz'**
  String get discountThresholdExceedsMax;

  /// No description provided for @salePreferencesSavedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Satış tercihleri başarıyla kaydedildi'**
  String get salePreferencesSavedSuccessfully;

  /// No description provided for @errorSavingPreferences.
  ///
  /// In tr, this message translates to:
  /// **'Satış tercihleri kaydedilirken hata oluştu'**
  String get errorSavingPreferences;

  /// Label indicating a product's best seller rank in its subcategory
  ///
  /// In tr, this message translates to:
  /// **'{subcategory} Kategorisinde En Çok Satan #{rank}'**
  String bestSellerLabel(int rank, String subcategory);

  /// No description provided for @required.
  ///
  /// In tr, this message translates to:
  /// **'Zorunlu'**
  String get required;

  /// No description provided for @removeDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirimi kaldır'**
  String get removeDiscount;

  /// No description provided for @unfollow.
  ///
  /// In tr, this message translates to:
  /// **'Takipden çık'**
  String get unfollow;

  /// No description provided for @searchInStore.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanda ara'**
  String get searchInStore;

  /// No description provided for @man.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get man;

  /// No description provided for @woman.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get woman;

  /// No description provided for @averageRating.
  ///
  /// In tr, this message translates to:
  /// **'Ortalama Değerlendirme'**
  String get averageRating;

  /// No description provided for @views.
  ///
  /// In tr, this message translates to:
  /// **'Görüntüleme'**
  String get views;

  /// No description provided for @purchases.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alma'**
  String get purchases;

  /// No description provided for @colorVariants.
  ///
  /// In tr, this message translates to:
  /// **'Renk Seçenekleri'**
  String get colorVariants;

  /// No description provided for @back.
  ///
  /// In tr, this message translates to:
  /// **'Geri'**
  String get back;

  /// No description provided for @discountRangePlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'1-100'**
  String get discountRangePlaceholder;

  /// No description provided for @shopReview.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Değerlendirmesi'**
  String get shopReview;

  /// No description provided for @writeShopReview.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan için bir değerlendirme yazın'**
  String get writeShopReview;

  /// Davet mesajı: davet edenin adı ve mağaza adı kullanılıyor.
  ///
  /// In tr, this message translates to:
  /// **'{shopName} mağazasına katılmaya davet edildiniz.'**
  String invitationMessage(Object inviterName, Object shopName);

  /// No description provided for @allProducts.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Ürünler'**
  String get allProducts;

  /// No description provided for @dealProducts.
  ///
  /// In tr, this message translates to:
  /// **'Fırsat Ürünler'**
  String get dealProducts;

  /// No description provided for @selectSize.
  ///
  /// In tr, this message translates to:
  /// **'Beden'**
  String get selectSize;

  /// No description provided for @productFeatures.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Özellikleri'**
  String get productFeatures;

  /// No description provided for @errorLoadingShops.
  ///
  /// In tr, this message translates to:
  /// **'Diğer satıcılar yüklenirken hata oluştu'**
  String get errorLoadingShops;

  /// No description provided for @checkOtherSellers.
  ///
  /// In tr, this message translates to:
  /// **'Diğer Satıcılar'**
  String get checkOtherSellers;

  /// Label for pending shipment status
  ///
  /// In tr, this message translates to:
  /// **'Beklemede'**
  String get pendingStatus;

  /// No description provided for @noTransactionsFound.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi bir satış işlemi bulunamadı'**
  String get noTransactionsFound;

  /// No description provided for @selectDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih seç'**
  String get selectDate;

  /// No description provided for @becomeASeller.
  ///
  /// In tr, this message translates to:
  /// **'Nar24\'de Satıcı Ol'**
  String get becomeASeller;

  /// No description provided for @noDataForSelectedDates.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen tarihler için herhangi bilgi yok'**
  String get noDataForSelectedDates;

  /// No description provided for @noTransactionsForSelectedDates.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen tarihler için herhangi bir işlem yok'**
  String get noTransactionsForSelectedDates;

  /// No description provided for @singleDate.
  ///
  /// In tr, this message translates to:
  /// **'Tek Tarih'**
  String get singleDate;

  /// No description provided for @dateRange.
  ///
  /// In tr, this message translates to:
  /// **'Tarih Aralığı (Opsiyonel)'**
  String get dateRange;

  /// No description provided for @myReviews.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirmelerim'**
  String get myReviews;

  /// No description provided for @iAgreeToThe.
  ///
  /// In tr, this message translates to:
  /// **'Kabul ediyorum: '**
  String get iAgreeToThe;

  /// No description provided for @membershipAgreement.
  ///
  /// In tr, this message translates to:
  /// **'Üyelik Sözleşmesi'**
  String get membershipAgreement;

  /// No description provided for @oldLabel.
  ///
  /// In tr, this message translates to:
  /// **'ESKİ'**
  String get oldLabel;

  /// No description provided for @newLabel.
  ///
  /// In tr, this message translates to:
  /// **'YENİ'**
  String get newLabel;

  /// No description provided for @pleaseAcceptAgreement.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için üyelik sözleşmesini kabul etmelisiniz'**
  String get pleaseAcceptAgreement;

  /// No description provided for @termsOfUse.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları'**
  String get termsOfUse;

  /// No description provided for @pleaseAcceptBothAgreements.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için hem üyelik sözleşmesini hem de kullanım koşullarını kabul etmelisiniz'**
  String get pleaseAcceptBothAgreements;

  /// No description provided for @twoFactorSetupTitle.
  ///
  /// In tr, this message translates to:
  /// **'İki Adımlı Doğrulama'**
  String get twoFactorSetupTitle;

  /// No description provided for @twoFactorLoginTitle.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Doğrulaması'**
  String get twoFactorLoginTitle;

  /// No description provided for @twoFactorDisableTitle.
  ///
  /// In tr, this message translates to:
  /// **'2FA\'yı Devre Dışı Bırak'**
  String get twoFactorDisableTitle;

  /// No description provided for @twoFactorVerificationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama'**
  String get twoFactorVerificationTitle;

  /// No description provided for @twoFactorSetupSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızı korumak için ikinci bir doğrulama adımı ekleyin.'**
  String get twoFactorSetupSubtitle;

  /// No description provided for @twoFactorLoginSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Girişi tamamlamak için doğrulama kodunu girin.'**
  String get twoFactorLoginSubtitle;

  /// No description provided for @twoFactorDisableSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Devre dışı bırakmayı doğrulamak için kodu girin.'**
  String get twoFactorDisableSubtitle;

  /// No description provided for @twoFactorVerificationSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'6 haneli doğrulama kodunu girin'**
  String get twoFactorVerificationSubtitle;

  /// No description provided for @twoFactorSentTo.
  ///
  /// In tr, this message translates to:
  /// **'Kod gönderildi:'**
  String get twoFactorSentTo;

  /// No description provided for @twoFactorVerifyButton.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Doğrula'**
  String get twoFactorVerifyButton;

  /// No description provided for @resumeSale.
  ///
  /// In tr, this message translates to:
  /// **'Satışa aç'**
  String get resumeSale;

  /// No description provided for @twoFactorResendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Tekrar Gönder'**
  String get twoFactorResendCode;

  /// No description provided for @twoFactorResendIn.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar gönder'**
  String get twoFactorResendIn;

  /// No description provided for @twoFactorEmailFallback.
  ///
  /// In tr, this message translates to:
  /// **'SMS almazsanız, kodu e-posta ile göndereceğiz'**
  String get twoFactorEmailFallback;

  /// No description provided for @twoFactorCodeIncomplete.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen 6 haneli kodu tam olarak girin'**
  String get twoFactorCodeIncomplete;

  /// No description provided for @twoFactorResendError.
  ///
  /// In tr, this message translates to:
  /// **'Kod yeniden gönderilemedi.'**
  String get twoFactorResendError;

  /// No description provided for @twoFactorSetupError.
  ///
  /// In tr, this message translates to:
  /// **'2FA kurulumu başarısız. Lütfen tekrar deneyin.'**
  String get twoFactorSetupError;

  /// No description provided for @twoFactorDisableError.
  ///
  /// In tr, this message translates to:
  /// **'2FA devre dışı bırakma başarısız. Lütfen tekrar deneyin.'**
  String get twoFactorDisableError;

  /// No description provided for @phoneNumberRequired.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Numarası Gerekli'**
  String get phoneNumberRequired;

  /// No description provided for @phoneNumberRequiredDesc.
  ///
  /// In tr, this message translates to:
  /// **'2FA\'yı etkinleştirmek için telefon numaranızı girin'**
  String get phoneNumberRequiredDesc;

  /// No description provided for @twoFactorAddToAuthenticatorButton.
  ///
  /// In tr, this message translates to:
  /// **'Authenticator\'a ekle'**
  String get twoFactorAddToAuthenticatorButton;

  /// No description provided for @twoFactorQrSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İkinci bir cihazla QR kodunu tarayarak ekleyebilirsiniz.'**
  String get twoFactorQrSubtitle;

  /// No description provided for @twoFactorManualSetupTitle.
  ///
  /// In tr, this message translates to:
  /// **'Manuel kurulum'**
  String get twoFactorManualSetupTitle;

  /// No description provided for @twoFactorManualSetupHint.
  ///
  /// In tr, this message translates to:
  /// **'Authenticator uygulamasında \'Anahtarı elle gir\' seçeneğini kullanın. Tür: Zaman tabanlı (TOTP), 6 hane, 30 sn.'**
  String get twoFactorManualSetupHint;

  /// No description provided for @copy.
  ///
  /// In tr, this message translates to:
  /// **'Kopyala'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In tr, this message translates to:
  /// **'Kopyalandı'**
  String get copied;

  /// No description provided for @twoFactorOpenAuthenticatorFailed.
  ///
  /// In tr, this message translates to:
  /// **'Authenticator açılamadı. Uygulama yüklü mü?'**
  String get twoFactorOpenAuthenticatorFailed;

  /// No description provided for @twoFactorEnter6DigitsBelow.
  ///
  /// In tr, this message translates to:
  /// **'Authenticator\'daki 6 haneli kodu aşağıya girin.'**
  String get twoFactorEnter6DigitsBelow;

  /// No description provided for @twoFactorEmailCodeSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu e-posta ile gönderildi.'**
  String get twoFactorEmailCodeSent;

  /// No description provided for @twoFactorEnabledSuccess.
  ///
  /// In tr, this message translates to:
  /// **'İki faktörlü doğrulama etkinleştirildi!'**
  String get twoFactorEnabledSuccess;

  /// No description provided for @twoFactorDisabledSuccess.
  ///
  /// In tr, this message translates to:
  /// **'İki faktörlü doğrulama devre dışı bırakıldı!'**
  String get twoFactorDisabledSuccess;

  /// No description provided for @twoFactorVerificationSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama başarılı!'**
  String get twoFactorVerificationSuccess;

  /// No description provided for @twoFactorCodeNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kod bulunamadı. Lütfen yeni bir kod isteyin.'**
  String get twoFactorCodeNotFound;

  /// No description provided for @twoFactorCodeExpired.
  ///
  /// In tr, this message translates to:
  /// **'Kodun süresi doldu. Lütfen yeni kod isteyin.'**
  String get twoFactorCodeExpired;

  /// No description provided for @twoFactorTooManyAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla başarısız deneme. Lütfen yeni kod isteyin.'**
  String get twoFactorTooManyAttempts;

  /// No description provided for @twoFactorInvalidCodeWithRemaining.
  ///
  /// In tr, this message translates to:
  /// **'{remaining} deneme kaldı.'**
  String twoFactorInvalidCodeWithRemaining(Object remaining);

  /// No description provided for @twoFactorEnterAuthenticatorCode.
  ///
  /// In tr, this message translates to:
  /// **'Authenticator uygulamanızdan 6 haneli kodu girin.'**
  String get twoFactorEnterAuthenticatorCode;

  /// No description provided for @twoFactorEnterAuthenticatorCodeToDisable.
  ///
  /// In tr, this message translates to:
  /// **'Devre dışı bırakmak için Authenticator kodunu girin.'**
  String get twoFactorEnterAuthenticatorCodeToDisable;

  /// No description provided for @refundFormTitle.
  ///
  /// In tr, this message translates to:
  /// **'İade Talebi'**
  String get refundFormTitle;

  /// No description provided for @refundFormHeaderTitle.
  ///
  /// In tr, this message translates to:
  /// **'İade Talebinde Bulunun'**
  String get refundFormHeaderTitle;

  /// No description provided for @refundFormHeaderSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İade talebinizi göndermek için aşağıdaki formu doldurun'**
  String get refundFormHeaderSubtitle;

  /// No description provided for @refundFormNameLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ad / Soyad'**
  String get refundFormNameLabel;

  /// No description provided for @refundFormNoName.
  ///
  /// In tr, this message translates to:
  /// **'İsim yok'**
  String get refundFormNoName;

  /// No description provided for @refundFormEmailLabel.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Adresi'**
  String get refundFormEmailLabel;

  /// No description provided for @refundFormReceiptNoLabel.
  ///
  /// In tr, this message translates to:
  /// **'Fatura Numarası'**
  String get refundFormReceiptNoLabel;

  /// No description provided for @refundFormFindReceipt.
  ///
  /// In tr, this message translates to:
  /// **'Fatura Bul'**
  String get refundFormFindReceipt;

  /// No description provided for @refundForm.
  ///
  /// In tr, this message translates to:
  /// **'İade Formu'**
  String get refundForm;

  /// No description provided for @refundFormReceiptNoPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Fatura numaranızı girin'**
  String get refundFormReceiptNoPlaceholder;

  /// No description provided for @refundFormDescriptionLabel.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get refundFormDescriptionLabel;

  /// No description provided for @refundFormDescriptionPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen iade talebinizin nedenini detaylı olarak açıklayın...'**
  String get refundFormDescriptionPlaceholder;

  /// No description provided for @refundFormDescriptionHelper.
  ///
  /// In tr, this message translates to:
  /// **'En az 20 karakter gereklidir'**
  String get refundFormDescriptionHelper;

  /// No description provided for @contactSupport.
  ///
  /// In tr, this message translates to:
  /// **'Desteğe Ulaşın'**
  String get contactSupport;

  /// No description provided for @helpFormTitle.
  ///
  /// In tr, this message translates to:
  /// **'Destek Talebi'**
  String get helpFormTitle;

  /// No description provided for @nameLabel.
  ///
  /// In tr, this message translates to:
  /// **'Ad / Soyad'**
  String get nameLabel;

  /// No description provided for @noName.
  ///
  /// In tr, this message translates to:
  /// **'İsim Yok'**
  String get noName;

  /// No description provided for @descriptionLabel.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama'**
  String get descriptionLabel;

  /// No description provided for @descriptionPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen size nasıl yardımcı olabileceğimizi açıklayın...'**
  String get descriptionPlaceholder;

  /// No description provided for @descriptionHelper.
  ///
  /// In tr, this message translates to:
  /// **'En az 20 karakter gereklidir'**
  String get descriptionHelper;

  /// No description provided for @descriptionRequired.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama gereklidir'**
  String get descriptionRequired;

  /// No description provided for @descriptionTooShort.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama en az 20 karakter olmalıdır'**
  String get descriptionTooShort;

  /// No description provided for @submitButton.
  ///
  /// In tr, this message translates to:
  /// **'Talebi Gönder'**
  String get submitButton;

  /// No description provided for @submitting.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get submitting;

  /// No description provided for @submitError.
  ///
  /// In tr, this message translates to:
  /// **'İade talebi gönderilemedi. Lütfen tekrar deneyin.'**
  String get submitError;

  /// No description provided for @successTitle.
  ///
  /// In tr, this message translates to:
  /// **'Talep Gönderildi!'**
  String get successTitle;

  /// No description provided for @submitSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Talebiniz başarıyla gönderildi. En kısa sürede inceleyeceğiz.'**
  String get submitSuccess;

  /// No description provided for @refundFormSubmitButton.
  ///
  /// In tr, this message translates to:
  /// **'Talebi Gönder'**
  String get refundFormSubmitButton;

  /// No description provided for @refundFormSubmitting.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get refundFormSubmitting;

  /// No description provided for @refundFormInfoMessage.
  ///
  /// In tr, this message translates to:
  /// **'İade talebiniz ekibimiz tarafından 3-5 iş günü içinde incelenecektir. Talebinizin durumu hakkında e-posta bildirimi alacaksınız.'**
  String get refundFormInfoMessage;

  /// No description provided for @receiptNoRequired.
  ///
  /// In tr, this message translates to:
  /// **'Fatura numarası gereklidir'**
  String get receiptNoRequired;

  /// No description provided for @refundFormSuccessTitle.
  ///
  /// In tr, this message translates to:
  /// **'Talep Gönderildi!'**
  String get refundFormSuccessTitle;

  /// No description provided for @refundFormSubmitSuccess.
  ///
  /// In tr, this message translates to:
  /// **'İade talebiniz başarıyla gönderildi. En kısa sürede inceleyeceğiz.'**
  String get refundFormSubmitSuccess;

  /// No description provided for @twoFactorInitError.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama başlatılırken hata oluştu.'**
  String get twoFactorInitError;

  /// No description provided for @twoFactorVerificationError.
  ///
  /// In tr, this message translates to:
  /// **'Hata oluştu. Cihazınızın saat ayarı otomatikde olduğundan emin olunuz.'**
  String get twoFactorVerificationError;

  /// No description provided for @twoFactorResendNotApplicableForTotp.
  ///
  /// In tr, this message translates to:
  /// **'TOTP için yeniden gönderme yoktur.'**
  String get twoFactorResendNotApplicableForTotp;

  /// No description provided for @shopReceipts.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza faturaları ve ödeme geçmişi'**
  String get shopReceipts;

  /// No description provided for @noReceipts.
  ///
  /// In tr, this message translates to:
  /// **'Henüz fatura yok'**
  String get noReceipts;

  /// No description provided for @noReceiptsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Faturalarınız burada görünecek'**
  String get noReceiptsDescription;

  /// No description provided for @failedToSendReceipt.
  ///
  /// In tr, this message translates to:
  /// **'Fatura gönderilemedi. Lütfen tekrar deneyin.'**
  String get failedToSendReceipt;

  /// No description provided for @sendReceipt.
  ///
  /// In tr, this message translates to:
  /// **'Fatura Gönder'**
  String get sendReceipt;

  /// No description provided for @orderIdCopied.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş numarası panoya kopyalandı'**
  String get orderIdCopied;

  /// No description provided for @boostReceipt.
  ///
  /// In tr, this message translates to:
  /// **'Boost Faturası'**
  String get boostReceipt;

  /// No description provided for @boostInformation.
  ///
  /// In tr, this message translates to:
  /// **'Boost Bilgileri'**
  String get boostInformation;

  /// No description provided for @boostedItems.
  ///
  /// In tr, this message translates to:
  /// **'Boost Edilen Ürünler'**
  String get boostedItems;

  /// No description provided for @totalPaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödenen Toplam'**
  String get totalPaid;

  /// No description provided for @paymentInformation.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Bilgileri'**
  String get paymentInformation;

  /// No description provided for @paymentStatus.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Durumu'**
  String get paymentStatus;

  /// No description provided for @seconds.
  ///
  /// In tr, this message translates to:
  /// **'saniye'**
  String get seconds;

  /// No description provided for @mesafeliSatisSozlesmesi.
  ///
  /// In tr, this message translates to:
  /// **'Mesafeli Satış Sözleşmesi'**
  String get mesafeliSatisSozlesmesi;

  /// No description provided for @saticiUyelikVeIsOrtakligi.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Üyelik ve İş Ortaklığı Sözleşmesi'**
  String get saticiUyelikVeIsOrtakligi;

  /// No description provided for @pleaseLogin.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen giriş yapın'**
  String get pleaseLogin;

  /// No description provided for @supportAndFaq.
  ///
  /// In tr, this message translates to:
  /// **'Destek ve SSS'**
  String get supportAndFaq;

  /// No description provided for @supportTitle.
  ///
  /// In tr, this message translates to:
  /// **'Size nasıl yardımcı olabiliriz?'**
  String get supportTitle;

  /// No description provided for @supportSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Sıkça sorulan soruların cevaplarını bulun veya destek ekibimizle iletişime geçin'**
  String get supportSubtitle;

  /// No description provided for @frequentlyAskedQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Sıkça Sorulan Sorular'**
  String get frequentlyAskedQuestions;

  /// No description provided for @stillNeedHelp.
  ///
  /// In tr, this message translates to:
  /// **'Hala yardıma mı ihtiyacınız var?'**
  String get stillNeedHelp;

  /// No description provided for @stillNeedHelpDescription.
  ///
  /// In tr, this message translates to:
  /// **'Aradığınızı bulamıyor musunuz? Destek ekibimiz size yardımcı olmak için burada.'**
  String get stillNeedHelpDescription;

  /// No description provided for @emailSupport.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get emailSupport;

  /// No description provided for @liveChat.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Sohbet'**
  String get liveChat;

  /// No description provided for @emailSupportMessage.
  ///
  /// In tr, this message translates to:
  /// **'E-posta destek talebi başarıyla gönderildi!'**
  String get emailSupportMessage;

  /// No description provided for @liveChatMessage.
  ///
  /// In tr, this message translates to:
  /// **'Canlı sohbete bağlanıyorsunuz...'**
  String get liveChatMessage;

  /// No description provided for @accountSettings.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Ayarları'**
  String get accountSettings;

  /// No description provided for @accountSettingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızı Yönetin'**
  String get accountSettingsTitle;

  /// No description provided for @accountSettingsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik ve bildirim tercihlerinizi kontrol edin'**
  String get accountSettingsSubtitle;

  /// No description provided for @securitySettings.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik ve Gizlilik'**
  String get securitySettings;

  /// No description provided for @twoFactorAuth.
  ///
  /// In tr, this message translates to:
  /// **'İki Faktörlü Doğrulama'**
  String get twoFactorAuth;

  /// No description provided for @twoFactorAuthDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınıza ek bir güvenlik katmanı ekleyin'**
  String get twoFactorAuthDesc;

  /// No description provided for @twoFactorEnabled.
  ///
  /// In tr, this message translates to:
  /// **'İki faktörlü doğrulama başarıyla etkinleştirildi!'**
  String get twoFactorEnabled;

  /// No description provided for @twoFactorDisabled.
  ///
  /// In tr, this message translates to:
  /// **'İki faktörlü doğrulama devre dışı bırakıldı'**
  String get twoFactorDisabled;

  /// No description provided for @notificationSettings.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim Tercihleri'**
  String get notificationSettings;

  /// No description provided for @allNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Bildirimler'**
  String get allNotifications;

  /// No description provided for @allNotificationsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Tüm bildirim türlerini etkinleştir veya devre dışı bırak'**
  String get allNotificationsDesc;

  /// No description provided for @emailNotifications.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Bildirimleri'**
  String get emailNotifications;

  /// No description provided for @emailNotificationsDesc.
  ///
  /// In tr, this message translates to:
  /// **'E-posta ile bildirim al'**
  String get emailNotificationsDesc;

  /// No description provided for @pushNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Anlık Bildirimler'**
  String get pushNotifications;

  /// No description provided for @pushNotificationsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Cihazınızda anlık bildirimler alın'**
  String get pushNotificationsDesc;

  /// No description provided for @smsNotifications.
  ///
  /// In tr, this message translates to:
  /// **'SMS Bildirimleri'**
  String get smsNotifications;

  /// No description provided for @smsNotificationsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Kısa mesaj ile bildirim al'**
  String get smsNotificationsDesc;

  /// No description provided for @dangerZone.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Silme'**
  String get dangerZone;

  /// No description provided for @deleteAccountDesc.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızı ve tüm ilişkili verileri kalıcı olarak silin'**
  String get deleteAccountDesc;

  /// No description provided for @faqShippingQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Kargo ne kadar sürer?'**
  String get faqShippingQuestion;

  /// No description provided for @faqShippingAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Standart kargo genellikle 3-7 iş günü sürer. 1-2 iş günü için ekspres kargo mevcuttur. Kargo süreleri konumunuza ve ürün mevcudiyetine göre değişebilir.'**
  String get faqShippingAnswer;

  /// No description provided for @faqReturnQuestion.
  ///
  /// In tr, this message translates to:
  /// **'İade politikanız nedir?'**
  String get faqReturnQuestion;

  /// No description provided for @faqReturnAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Çoğu ürün için 30 günlük iade politikası sunuyoruz. Ürünler etiketleri ile birlikte orijinal durumda olmalıdır. Dijital ürünler ve kişiselleştirilmiş ürünler iade edilemez.'**
  String get faqReturnAnswer;

  /// No description provided for @faqPaymentQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Hangi ödeme yöntemlerini kabul ediyorsunuz?'**
  String get faqPaymentQuestion;

  /// No description provided for @faqPaymentAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Tüm büyük kredi kartlarını (Visa, Mastercard, American Express), PayPal, Apple Pay, Google Pay ve banka havalelerini kabul ediyoruz. Tüm ödemeler güvenli şekilde işlenir.'**
  String get faqPaymentAnswer;

  /// No description provided for @faqAccountQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Nasıl hesap oluştururum?'**
  String get faqAccountQuestion;

  /// No description provided for @faqAccountAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Giriş sayfasındaki \'Kayıt Ol\' butonuna tıklayın, e-postanızı girin ve şifre oluşturun. Daha hızlı kayıt için Google veya Facebook hesabınızla da kayıt olabilirsiniz.'**
  String get faqAccountAnswer;

  /// No description provided for @faqOrderQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Siparişimi nasıl takip edebilirim?'**
  String get faqOrderQuestion;

  /// No description provided for @faqOrderAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Siparişiniz kargoya verildiğinde, e-posta ile takip numarası alacaksınız. Ayrıca hesabınızdaki \'Siparişlerim\' bölümünden sipariş durumunuzu kontrol edebilirsiniz.'**
  String get faqOrderAnswer;

  /// No description provided for @faqRefundQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Geri ödemeler nasıl çalışır?'**
  String get faqRefundQuestion;

  /// No description provided for @faqRefundAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Geri ödemeler, iadenizi aldıktan sonra 5-10 iş günü içinde işlenir. Geri ödeme orijinal ödeme yönteminize aktarılır.'**
  String get faqRefundAnswer;

  /// No description provided for @faqSellerQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Nasıl satıcı olurum?'**
  String get faqSellerQuestion;

  /// No description provided for @faqSellerAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı olmak için profilinize gidin ve \'Satıcı Ol\' butonuna tıklayın. İşletme bilgilerini, vergi detaylarını sağlamanız ve kimliğinizi doğrulamanız gerekir.'**
  String get faqSellerAnswer;

  /// No description provided for @faqSafetyQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel bilgilerim güvende mi?'**
  String get faqSafetyQuestion;

  /// No description provided for @faqSafetyAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Evet, kişisel ve ödeme bilgilerinizi korumak için endüstri standardı şifreleme ve güvenlik önlemleri kullanıyoruz. Verilerinizi rızanız olmadan üçüncü taraflarla asla paylaşmayız.'**
  String get faqSafetyAnswer;

  /// No description provided for @noPurchases.
  ///
  /// In tr, this message translates to:
  /// **'Satın alınmış ürün bulunamadı.'**
  String get noPurchases;

  /// No description provided for @allReviewed.
  ///
  /// In tr, this message translates to:
  /// **'Tüm satın alınan ürünler zaten incelendi.'**
  String get allReviewed;

  /// No description provided for @productReview.
  ///
  /// In tr, this message translates to:
  /// **'Ürün İncelemesi'**
  String get productReview;

  /// No description provided for @writeProductReview.
  ///
  /// In tr, this message translates to:
  /// **'Ürün incelemenizi yazın'**
  String get writeProductReview;

  /// No description provided for @productReviewRequired.
  ///
  /// In tr, this message translates to:
  /// **'Ürün incelemesi zorunludur.'**
  String get productReviewRequired;

  /// No description provided for @fabricType.
  ///
  /// In tr, this message translates to:
  /// **'Kumaş Tipi'**
  String get fabricType;

  /// No description provided for @pleaseSelectAtLeastOneFabricType.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir kumaş tipi seçin'**
  String get pleaseSelectAtLeastOneFabricType;

  /// No description provided for @maxFabricTypesSelected.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 4 kumaş tipi seçilebilir'**
  String get maxFabricTypesSelected;

  /// No description provided for @clothingTypeLyocell.
  ///
  /// In tr, this message translates to:
  /// **'Liyosel'**
  String get clothingTypeLyocell;

  /// No description provided for @clothingTypeOrganicCotton.
  ///
  /// In tr, this message translates to:
  /// **'Organik Pamuk'**
  String get clothingTypeOrganicCotton;

  /// No description provided for @clothingTypeRecycledCotton.
  ///
  /// In tr, this message translates to:
  /// **'Geri Dönüşüm Pamuk'**
  String get clothingTypeRecycledCotton;

  /// No description provided for @clothingTypeCanvas.
  ///
  /// In tr, this message translates to:
  /// **'Kanvas'**
  String get clothingTypeCanvas;

  /// No description provided for @clothingTypeJersey.
  ///
  /// In tr, this message translates to:
  /// **'Jarse'**
  String get clothingTypeJersey;

  /// No description provided for @clothingTypeGabardine.
  ///
  /// In tr, this message translates to:
  /// **'Gabardin'**
  String get clothingTypeGabardine;

  /// No description provided for @clothingTypeSatin.
  ///
  /// In tr, this message translates to:
  /// **'Saten'**
  String get clothingTypeSatin;

  /// No description provided for @clothingTypeRayon.
  ///
  /// In tr, this message translates to:
  /// **'Rayon'**
  String get clothingTypeRayon;

  /// No description provided for @clothingTypeElastane.
  ///
  /// In tr, this message translates to:
  /// **'Elastan'**
  String get clothingTypeElastane;

  /// No description provided for @clothingTypeBamboo.
  ///
  /// In tr, this message translates to:
  /// **'Bambu'**
  String get clothingTypeBamboo;

  /// No description provided for @clothingTypeVelvet.
  ///
  /// In tr, this message translates to:
  /// **'Kadife'**
  String get clothingTypeVelvet;

  /// No description provided for @clothingTypeFleece.
  ///
  /// In tr, this message translates to:
  /// **'Polar'**
  String get clothingTypeFleece;

  /// No description provided for @clothingTypeSpandex.
  ///
  /// In tr, this message translates to:
  /// **'Spandeks'**
  String get clothingTypeSpandex;

  /// No description provided for @clothingTypeTweed.
  ///
  /// In tr, this message translates to:
  /// **'Tüvit'**
  String get clothingTypeTweed;

  /// No description provided for @clothingTypeCorduroy.
  ///
  /// In tr, this message translates to:
  /// **'Fitilli Kadife'**
  String get clothingTypeCorduroy;

  /// No description provided for @clothingTypeChino.
  ///
  /// In tr, this message translates to:
  /// **'Çino'**
  String get clothingTypeChino;

  /// No description provided for @clothingTypeViscose.
  ///
  /// In tr, this message translates to:
  /// **'Viskon'**
  String get clothingTypeViscose;

  /// No description provided for @clothingTypeModal.
  ///
  /// In tr, this message translates to:
  /// **'Modal'**
  String get clothingTypeModal;

  /// No description provided for @sellerReview.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı İncelemesi'**
  String get sellerReview;

  /// No description provided for @discountHelperText.
  ///
  /// In tr, this message translates to:
  /// **'%1 ile %100 arasında bir indirim yüzdesi girin'**
  String get discountHelperText;

  /// No description provided for @pullToRefresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenilemek için aşağı çekin'**
  String get pullToRefresh;

  /// No description provided for @noRecommendationsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz öneri yok'**
  String get noRecommendationsYet;

  /// No description provided for @startBrowsingToGetRecommendations.
  ///
  /// In tr, this message translates to:
  /// **'Kişiselleştirilmiş öneriler almak için taramaya başlayın'**
  String get startBrowsingToGetRecommendations;

  /// No description provided for @validDiscountMessage.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli indirim yüzdesi'**
  String get validDiscountMessage;

  /// No description provided for @bulkDiscountHelper.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut indirimi olmayan tüm filtrelenmiş ürünlere indirim uygula'**
  String get bulkDiscountHelper;

  /// No description provided for @individualDiscountHelper.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün için bir indirim yüzdesi girin'**
  String get individualDiscountHelper;

  /// No description provided for @categoryDiscountHelper.
  ///
  /// In tr, this message translates to:
  /// **'Bu kategorideki tüm ürünlere indirim uygula'**
  String get categoryDiscountHelper;

  /// No description provided for @newPrice.
  ///
  /// In tr, this message translates to:
  /// **'Yeni fiyat:'**
  String get newPrice;

  /// No description provided for @collectionNameHelper.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyonunuzu tanımlayan bir isim seçin'**
  String get collectionNameHelper;

  /// No description provided for @editing.
  ///
  /// In tr, this message translates to:
  /// **'Düzenleniyor'**
  String get editing;

  /// No description provided for @deleteCollectionWarning.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem geri alınamaz. Ürünler silinmeyecektir.'**
  String get deleteCollectionWarning;

  /// No description provided for @writeSellerReview.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı incelemenizi yazın (isteğe bağlı)'**
  String get writeSellerReview;

  /// No description provided for @submitReview.
  ///
  /// In tr, this message translates to:
  /// **'Yorum gönder'**
  String get submitReview;

  /// No description provided for @reviewSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'İnceleme başarıyla gönderildi!'**
  String get reviewSubmitted;

  /// No description provided for @shopApplicationSent.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan başvurusu başarıyla gönderildi.'**
  String get shopApplicationSent;

  /// No description provided for @panel.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Paneli >'**
  String get panel;

  /// No description provided for @goToShop.
  ///
  /// In tr, this message translates to:
  /// **'Mağazaya git'**
  String get goToShop;

  /// No description provided for @carTypePlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Araba Türü'**
  String get carTypePlaceholder;

  /// No description provided for @userAlsoBoughtThese.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar bu ürünleride satın aldı'**
  String get userAlsoBoughtThese;

  /// No description provided for @cannotSetSalePreferenceWithDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Üründe indirim varken bu işlem yapılamaz'**
  String get cannotSetSalePreferenceWithDiscount;

  /// No description provided for @salePreferenceRemovedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Satış tercihleri başarıyla kaldırıldı'**
  String get salePreferenceRemovedSuccessfully;

  /// No description provided for @errorRemovingSalePreference.
  ///
  /// In tr, this message translates to:
  /// **'Satış tercihleri kaldırılırken hata oluştu'**
  String get errorRemovingSalePreference;

  /// No description provided for @removeSalePreferenceToCreateBundle.
  ///
  /// In tr, this message translates to:
  /// **'Bu üründen indirimli satış tercihi kaldırılmadan paket oluşturulamaz'**
  String get removeSalePreferenceToCreateBundle;

  /// No description provided for @pleaseAddImageForColor.
  ///
  /// In tr, this message translates to:
  /// **'Dilerseniz her seçilen renk için görsel yükleyebilirsiniz'**
  String get pleaseAddImageForColor;

  /// No description provided for @pleaseEnterQuantityForColor.
  ///
  /// In tr, this message translates to:
  /// **'Renk seçeneği için miktar girin'**
  String get pleaseEnterQuantityForColor;

  /// No description provided for @myAdresses.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı Adreslerim'**
  String get myAdresses;

  /// No description provided for @points.
  ///
  /// In tr, this message translates to:
  /// **'Kazandığım Puanlar'**
  String get points;

  /// No description provided for @newAddress.
  ///
  /// In tr, this message translates to:
  /// **'Yeni adres'**
  String get newAddress;

  /// No description provided for @shareFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorileri Paylaş'**
  String get shareFavorites;

  /// No description provided for @selectFavoritesToShare.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşılacak favorileri seçin'**
  String get selectFavoritesToShare;

  /// No description provided for @general.
  ///
  /// In tr, this message translates to:
  /// **'Genel'**
  String get general;

  /// No description provided for @importingFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler içe aktarılıyor...'**
  String get importingFavorites;

  /// No description provided for @favoritesImported.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler başarıyla içe aktarıldı'**
  String get favoritesImported;

  /// No description provided for @cannotAddFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Sepet limitine ulaştığınız için {name}\'in favorileri eklenemiyor'**
  String cannotAddFavorites(String name);

  /// No description provided for @errorImportingFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler içe aktarılırken hata oluştu'**
  String get errorImportingFavorites;

  /// No description provided for @noFavoritesToShare.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşılacak favori yok'**
  String get noFavoritesToShare;

  /// No description provided for @favoritesShared.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler başarıyla paylaşıldı!'**
  String get favoritesShared;

  /// No description provided for @myOrders.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Siparişlerim'**
  String get myOrders;

  /// No description provided for @addNewAddress.
  ///
  /// In tr, this message translates to:
  /// **'Yeni adres ekle'**
  String get addNewAddress;

  /// No description provided for @selectCity.
  ///
  /// In tr, this message translates to:
  /// **'Bölge seçin'**
  String get selectCity;

  /// No description provided for @noResultsFound.
  ///
  /// In tr, this message translates to:
  /// **'Arama sonucu bulunamadı'**
  String get noResultsFound;

  /// No description provided for @tryDifferentKeywords.
  ///
  /// In tr, this message translates to:
  /// **'Farklı kelimeler kullanmayı deneyin'**
  String get tryDifferentKeywords;

  /// No description provided for @browseCategories.
  ///
  /// In tr, this message translates to:
  /// **'Kategorileri Keşfet'**
  String get browseCategories;

  /// No description provided for @yourPurchaseReceiptsWillAppearHere.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma makbuzlarınız burada görünecek'**
  String get yourPurchaseReceiptsWillAppearHere;

  /// No description provided for @daysAgo.
  ///
  /// In tr, this message translates to:
  /// **'gün önce'**
  String get daysAgo;

  /// No description provided for @card.
  ///
  /// In tr, this message translates to:
  /// **'Kart'**
  String get card;

  /// No description provided for @cash.
  ///
  /// In tr, this message translates to:
  /// **'Nakit'**
  String get cash;

  /// No description provided for @bankTransfer.
  ///
  /// In tr, this message translates to:
  /// **'Banka Havalesi'**
  String get bankTransfer;

  /// No description provided for @normal.
  ///
  /// In tr, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @nar24Delivery.
  ///
  /// In tr, this message translates to:
  /// **'Nar24 Teslimatı'**
  String get nar24Delivery;

  /// No description provided for @noSavedAddresses.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı adresiniz bulunmamaktadır'**
  String get noSavedAddresses;

  /// No description provided for @chooseLocation.
  ///
  /// In tr, this message translates to:
  /// **'Haritada Konum Seç'**
  String get chooseLocation;

  /// No description provided for @sellOnVitrin.
  ///
  /// In tr, this message translates to:
  /// **'Vitrin\'de Sat'**
  String get sellOnVitrin;

  /// No description provided for @quantityForColor.
  ///
  /// In tr, this message translates to:
  /// **'Renk seçeneği miktarı'**
  String get quantityForColor;

  /// No description provided for @searchFailedTryAgain.
  ///
  /// In tr, this message translates to:
  /// **'Arama başarısız, tekrar deneyin.'**
  String get searchFailedTryAgain;

  /// No description provided for @waitingForAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevap bekleniyor'**
  String get waitingForAnswer;

  /// No description provided for @userQuestionsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sorularım'**
  String get userQuestionsTitle;

  /// No description provided for @askedQuestionsTabLabel.
  ///
  /// In tr, this message translates to:
  /// **'Sorduğum Sorular'**
  String get askedQuestionsTabLabel;

  /// No description provided for @receivedQuestionsTabLabel.
  ///
  /// In tr, this message translates to:
  /// **'Aldığım Sorular'**
  String get receivedQuestionsTabLabel;

  /// No description provided for @myQuestions.
  ///
  /// In tr, this message translates to:
  /// **'Sorularım'**
  String get myQuestions;

  /// No description provided for @sellerPanel.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Paneli'**
  String get sellerPanel;

  /// No description provided for @stockValidationError2.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünler stokta kalmadı: '**
  String get stockValidationError2;

  /// No description provided for @refreshCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepeti yeniden yükle'**
  String get refreshCart;

  /// No description provided for @dashboard.
  ///
  /// In tr, this message translates to:
  /// **'Genel'**
  String get dashboard;

  /// No description provided for @stockIssuesDetected.
  ///
  /// In tr, this message translates to:
  /// **'Bazı ürünler stokta kalmadı'**
  String get stockIssuesDetected;

  /// No description provided for @transactions.
  ///
  /// In tr, this message translates to:
  /// **'İşlemler'**
  String get transactions;

  /// No description provided for @shipments.
  ///
  /// In tr, this message translates to:
  /// **'Sevkiyatlar'**
  String get shipments;

  /// No description provided for @stockValidationError4.
  ///
  /// In tr, this message translates to:
  /// **'ürün(ler) şuan uygun değil'**
  String get stockValidationError4;

  /// No description provided for @stockValidationError3.
  ///
  /// In tr, this message translates to:
  /// **' ürün(ler) şuan stokta kalmadı'**
  String get stockValidationError3;

  /// No description provided for @unavailable.
  ///
  /// In tr, this message translates to:
  /// **'Uygun değil'**
  String get unavailable;

  /// Bir ürünün stokta kalmadığını belirtmek için gösterilecek mesaj
  ///
  /// In tr, this message translates to:
  /// **'{productName} stokta kalmadı. Lütfen satın almaya devam etmeden önce sepetinizden çıkarın.'**
  String productOutOfStock(Object productName);

  /// No description provided for @productNoLongerAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Ürün artık mevcut değil'**
  String get productNoLongerAvailable;

  /// No description provided for @passwordRequirements.
  ///
  /// In tr, this message translates to:
  /// **'Şifre Gereksinimleri:'**
  String get passwordRequirements;

  /// No description provided for @passwordMinLength.
  ///
  /// In tr, this message translates to:
  /// **'En az 8 karakter'**
  String get passwordMinLength;

  /// No description provided for @passwordUppercase.
  ///
  /// In tr, this message translates to:
  /// **'Bir büyük harf (A-Z)'**
  String get passwordUppercase;

  /// No description provided for @passwordLowercase.
  ///
  /// In tr, this message translates to:
  /// **'Bir küçük harf (a-z)'**
  String get passwordLowercase;

  /// No description provided for @passwordDigit.
  ///
  /// In tr, this message translates to:
  /// **'Bir rakam (0-9)'**
  String get passwordDigit;

  /// No description provided for @passwordSpecialChar.
  ///
  /// In tr, this message translates to:
  /// **'Bir özel karakter (!@#\$%...)'**
  String get passwordSpecialChar;

  /// No description provided for @passwordDoesNotMeetRequirements.
  ///
  /// In tr, this message translates to:
  /// **'Şifre tüm gereksinimleri karşılamıyor'**
  String get passwordDoesNotMeetRequirements;

  /// No description provided for @paused.
  ///
  /// In tr, this message translates to:
  /// **'Durduruldu'**
  String get paused;

  /// No description provided for @requested.
  ///
  /// In tr, this message translates to:
  /// **'İstenilen'**
  String get requested;

  /// No description provided for @available.
  ///
  /// In tr, this message translates to:
  /// **'Uygun'**
  String get available;

  /// No description provided for @unnamedProduct.
  ///
  /// In tr, this message translates to:
  /// **'İsimsiz'**
  String get unnamedProduct;

  /// No description provided for @shopViews.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Ziyareti'**
  String get shopViews;

  /// Kalan miktarı gösteren metin, sayıyı içerir
  ///
  /// In tr, this message translates to:
  /// **'Son {quantity} tane'**
  String onlyLeft(Object quantity);

  /// No description provided for @mostViewedProduct.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Görüntülenen Ürün'**
  String get mostViewedProduct;

  /// No description provided for @mostAddedToCartProduct.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Sepete Eklenen Ürün'**
  String get mostAddedToCartProduct;

  /// No description provided for @mostFavoritedProduct.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Favorilere Eklenen Ürün'**
  String get mostFavoritedProduct;

  /// No description provided for @mostSoldProduct.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Satılan Ürün'**
  String get mostSoldProduct;

  /// No description provided for @noProductsSelected.
  ///
  /// In tr, this message translates to:
  /// **'Ürün seçilmedi'**
  String get noProductsSelected;

  /// No description provided for @categories.
  ///
  /// In tr, this message translates to:
  /// **'Kategoriler'**
  String get categories;

  /// No description provided for @boosts.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkar'**
  String get boosts;

  /// No description provided for @carts.
  ///
  /// In tr, this message translates to:
  /// **'Sepetler'**
  String get carts;

  /// No description provided for @productViews.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Gösterimi'**
  String get productViews;

  /// No description provided for @ads.
  ///
  /// In tr, this message translates to:
  /// **'Reklamlar'**
  String get ads;

  /// No description provided for @specStatus.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get specStatus;

  /// No description provided for @specFuelType.
  ///
  /// In tr, this message translates to:
  /// **'Yakıt Türü'**
  String get specFuelType;

  /// No description provided for @specTransmission.
  ///
  /// In tr, this message translates to:
  /// **'Şanzıman'**
  String get specTransmission;

  /// No description provided for @specEngineSize.
  ///
  /// In tr, this message translates to:
  /// **'Motor Hacmi'**
  String get specEngineSize;

  /// No description provided for @specHorsepower.
  ///
  /// In tr, this message translates to:
  /// **'Beygir Gücü'**
  String get specHorsepower;

  /// No description provided for @analytics.
  ///
  /// In tr, this message translates to:
  /// **'Analizler'**
  String get analytics;

  /// No description provided for @confirmDeletion.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Silme'**
  String get confirmDeletion;

  /// No description provided for @confirmDeletionMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü kalıcı olarak silmek istediğinizden emin misiniz?'**
  String get confirmDeletionMessage;

  /// No description provided for @pleaseUploadAtMostOneVideo.
  ///
  /// In tr, this message translates to:
  /// **'Sadece 1 video yüklenebilir'**
  String get pleaseUploadAtMostOneVideo;

  /// No description provided for @existingColorImages.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut renk seçenekleri'**
  String get existingColorImages;

  /// No description provided for @noSuggestions.
  ///
  /// In tr, this message translates to:
  /// **'Öneri yok'**
  String get noSuggestions;

  /// No description provided for @automobile.
  ///
  /// In tr, this message translates to:
  /// **'Araç'**
  String get automobile;

  /// No description provided for @suv.
  ///
  /// In tr, this message translates to:
  /// **'SUV'**
  String get suv;

  /// No description provided for @pickUp.
  ///
  /// In tr, this message translates to:
  /// **'Pick-up'**
  String get pickUp;

  /// No description provided for @motorcycle.
  ///
  /// In tr, this message translates to:
  /// **'Motorsiklet'**
  String get motorcycle;

  /// No description provided for @searchNoResults.
  ///
  /// In tr, this message translates to:
  /// **'Arama sonucu bulunamadı'**
  String get searchNoResults;

  /// No description provided for @sortBy.
  ///
  /// In tr, this message translates to:
  /// **'Sırala'**
  String get sortBy;

  /// No description provided for @none.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get none;

  /// No description provided for @alphabetical.
  ///
  /// In tr, this message translates to:
  /// **'Alfabetik'**
  String get alphabetical;

  /// No description provided for @createTweetAboutProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün hakkında\ntweet oluştur'**
  String get createTweetAboutProduct;

  /// No description provided for @checkTweetsAboutProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün hakkında\ntweetleri kontrol et'**
  String get checkTweetsAboutProduct;

  /// No description provided for @mostSearchedProducts.
  ///
  /// In tr, this message translates to:
  /// **'En çok aranan ürünler'**
  String get mostSearchedProducts;

  /// No description provided for @date.
  ///
  /// In tr, this message translates to:
  /// **'Tarih'**
  String get date;

  /// No description provided for @priceLowToHigh.
  ///
  /// In tr, this message translates to:
  /// **'Düşükten yükseğe fiyat'**
  String get priceLowToHigh;

  /// No description provided for @priceHighToLow.
  ///
  /// In tr, this message translates to:
  /// **'Yüksekten düşüğe fiyat'**
  String get priceHighToLow;

  /// No description provided for @priceRangeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Aralığı'**
  String get priceRangeLabel;

  /// Seçilen fiyat aralığını gösterir; {start} minimum, {end} maksimum fiyatı temsil eder.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat aralığı: {start} - {end}'**
  String priceRange(Object start, Object end);

  /// No description provided for @atvUtv.
  ///
  /// In tr, this message translates to:
  /// **'ATV & UTV'**
  String get atvUtv;

  /// No description provided for @caravan.
  ///
  /// In tr, this message translates to:
  /// **'Karavan'**
  String get caravan;

  /// No description provided for @commercialVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Ticari Araçlar'**
  String get commercialVehicles;

  /// No description provided for @minivanPanelvan.
  ///
  /// In tr, this message translates to:
  /// **'Minivan & Panelvan'**
  String get minivanPanelvan;

  /// No description provided for @classicCars.
  ///
  /// In tr, this message translates to:
  /// **'Klassic Araçlar'**
  String get classicCars;

  /// No description provided for @workVehicles.
  ///
  /// In tr, this message translates to:
  /// **'İş Araçları'**
  String get workVehicles;

  /// No description provided for @marineVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Deniz Araçları'**
  String get marineVehicles;

  /// No description provided for @brandPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Marka'**
  String get brandPlaceholder;

  /// No description provided for @brandNew.
  ///
  /// In tr, this message translates to:
  /// **'Sıfır'**
  String get brandNew;

  /// No description provided for @orderProcessedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Siparişiniz başarıyla işleme alındı'**
  String get orderProcessedSuccessfully;

  /// No description provided for @purchaseComplete.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Tamamlandı'**
  String get purchaseComplete;

  /// No description provided for @congratulationsSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla incelemeye gönderildi'**
  String get congratulationsSuccess;

  /// No description provided for @successDescription.
  ///
  /// In tr, this message translates to:
  /// **'İşleminiz başarıyla tamamlandı! Artık pazaryerini keşfedebilirsiniz.'**
  String get successDescription;

  /// No description provided for @exploreMarketplace.
  ///
  /// In tr, this message translates to:
  /// **'Pazaryerini Keşfet'**
  String get exploreMarketplace;

  /// No description provided for @marketplaceDescription.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulanmış satıcılarımızdan harika ürünler ve fırsatlar keşfedin'**
  String get marketplaceDescription;

  /// No description provided for @safeShoppingGuarantee.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli ve emniyetli alışveriş deneyimi garanti'**
  String get safeShoppingGuarantee;

  /// No description provided for @secondHand.
  ///
  /// In tr, this message translates to:
  /// **'2. El'**
  String get secondHand;

  /// No description provided for @status.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get status;

  /// No description provided for @statusPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Durum'**
  String get statusPlaceholder;

  /// No description provided for @fuelType.
  ///
  /// In tr, this message translates to:
  /// **'Yakıt tipi'**
  String get fuelType;

  /// No description provided for @fuelTypePlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Yakıt Türü'**
  String get fuelTypePlaceholder;

  /// No description provided for @productQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Sorusu'**
  String get productQuestion;

  /// No description provided for @gasoline.
  ///
  /// In tr, this message translates to:
  /// **'Benzin'**
  String get gasoline;

  /// No description provided for @diesel.
  ///
  /// In tr, this message translates to:
  /// **'Diesel'**
  String get diesel;

  /// No description provided for @electric.
  ///
  /// In tr, this message translates to:
  /// **'Elektrik'**
  String get electric;

  /// No description provided for @hybrid.
  ///
  /// In tr, this message translates to:
  /// **'Hybrid'**
  String get hybrid;

  /// No description provided for @transmission.
  ///
  /// In tr, this message translates to:
  /// **'Vites'**
  String get transmission;

  /// No description provided for @transmissionPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Şanzıman'**
  String get transmissionPlaceholder;

  /// No description provided for @automatic.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik'**
  String get automatic;

  /// No description provided for @manual.
  ///
  /// In tr, this message translates to:
  /// **'Manuel'**
  String get manual;

  /// No description provided for @currency.
  ///
  /// In tr, this message translates to:
  /// **'Para Birimi'**
  String get currency;

  /// No description provided for @addImages.
  ///
  /// In tr, this message translates to:
  /// **'Resim Ekle'**
  String get addImages;

  /// No description provided for @listCarButton.
  ///
  /// In tr, this message translates to:
  /// **'Araba Listele'**
  String get listCarButton;

  /// No description provided for @uploadAtLeastOneImage.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir mülk fotoğrafı yükleyin.'**
  String get uploadAtLeastOneImage;

  /// No description provided for @userNotFoundPleaseLoginAgain.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı bulunamadı, lütfen tekrar giriş yapınız.'**
  String get userNotFoundPleaseLoginAgain;

  /// No description provided for @carListedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Araç listeleme başarısı'**
  String get carListedSuccess;

  /// No description provided for @errorOccurredWithDetails.
  ///
  /// In tr, this message translates to:
  /// **'Bir hata oluştu: {error}'**
  String errorOccurredWithDetails(Object error);

  /// No description provided for @searchOrders.
  ///
  /// In tr, this message translates to:
  /// **'Siparişlerde ara'**
  String get searchOrders;

  /// No description provided for @noOrdersFoundForSearch.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş bulunamadı'**
  String get noOrdersFoundForSearch;

  /// No description provided for @trySearchingWithDifferentKeywords.
  ///
  /// In tr, this message translates to:
  /// **'Farklı bir arama yapmayı deneyin'**
  String get trySearchingWithDifferentKeywords;

  /// No description provided for @requiredField.
  ///
  /// In tr, this message translates to:
  /// **'{field} gerekli.'**
  String requiredField(Object field);

  /// No description provided for @selectPickupPoint.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktası Seç'**
  String get selectPickupPoint;

  /// No description provided for @searchPickupPoints.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al noktası ara...'**
  String get searchPickupPoints;

  /// No description provided for @noPickupPointsFound.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al noktası bulunamadı'**
  String get noPickupPointsFound;

  /// No description provided for @noPickupPointsAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al noktası mevcut değil'**
  String get noPickupPointsAvailable;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In tr, this message translates to:
  /// **'Farklı bir arama terimi deneyin'**
  String get tryDifferentSearch;

  /// No description provided for @pickupPoint.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktası'**
  String get pickupPoint;

  /// No description provided for @pickupPointDescription.
  ///
  /// In tr, this message translates to:
  /// **'Yakın lokasyondan teslim al'**
  String get pickupPointDescription;

  /// No description provided for @selectedPickupPoint.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen Gel Al Noktası'**
  String get selectedPickupPoint;

  /// No description provided for @change.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get change;

  /// No description provided for @pickupPointDetails.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktası Detayları'**
  String get pickupPointDetails;

  /// No description provided for @address.
  ///
  /// In tr, this message translates to:
  /// **'Adres'**
  String get address;

  /// No description provided for @operatingHours.
  ///
  /// In tr, this message translates to:
  /// **'Çalışma Saatleri'**
  String get operatingHours;

  /// No description provided for @contactPerson.
  ///
  /// In tr, this message translates to:
  /// **'İletişim Kişisi'**
  String get contactPerson;

  /// No description provided for @phoneNumber.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Numarası'**
  String get phoneNumber;

  /// No description provided for @productHasExistingDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünün zaten %{percentage} indirimi uygulanmış. Güncellemek için yeni bir değer girin veya mevcut indirimi korumak için boş bırakın.'**
  String productHasExistingDiscount(Object percentage);

  /// Ürünün geçerli mevcut indirimi olduğunda gösterilen mesaj
  ///
  /// In tr, this message translates to:
  /// **'Bu üründe %{percentage} indirim uygulanmış. Korumak için boş bırakın veya güncellemek için yeni değer girin.'**
  String productHasValidDiscount(String percentage);

  /// Mevcut indirim minimum eşiğin altında olduğunda gösterilen uyarı
  ///
  /// In tr, this message translates to:
  /// **'Mevcut indirim %{currentPercentage}. Minimum eşik %{minPercentage}. İndirim yüzdenizi güncellemeniz gerekiyor.'**
  String productDiscountBelowThreshold(
      String currentPercentage, String minPercentage);

  /// No description provided for @chooseRemovalOption.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü kampanyadan nasıl kaldırmak istediğinizi seçin:'**
  String get chooseRemovalOption;

  /// No description provided for @keepDiscountRemoveFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'İndirimi koru, kampanyadan kaldır'**
  String get keepDiscountRemoveFromCampaign;

  /// No description provided for @keepDiscountDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürün mevcut indirimini korur ancak artık bu kampanyanın parçası olmaz'**
  String get keepDiscountDescription;

  /// No description provided for @removeDiscountAndFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'İndirimi ve kampanyadan kaldır'**
  String get removeDiscountAndFromCampaign;

  /// No description provided for @removeDiscountDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürün fiyatı orijinal haline döner ve kampanyadan kaldırılır'**
  String get removeDiscountDescription;

  /// No description provided for @productRemovedDiscountKept.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kampanyadan kaldırıldı, indirim korundu'**
  String get productRemovedDiscountKept;

  /// No description provided for @productRemovedDiscountRestored.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kampanyadan kaldırıldı, orijinal fiyat geri yüklendi'**
  String get productRemovedDiscountRestored;

  /// No description provided for @discountAlreadyAppliedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Üründe Aktif İndirim Var'**
  String get discountAlreadyAppliedTitle;

  /// No description provided for @discountAlreadyAppliedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu üründe şu anda %{percentage} indirim uygulanmış. Satış tercihleri indirimli fiyat üzerinden hesaplanacaktır.'**
  String discountAlreadyAppliedMessage(Object percentage);

  /// No description provided for @salePreferencesDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Satış tercihleri başarıyla kaldırıldı'**
  String get salePreferencesDeleted;

  /// No description provided for @cannotApplyDiscountWithSalePreference.
  ///
  /// In tr, this message translates to:
  /// **'Bu üründe satış tercihleri olduğundan dolayı indirim uygulanamaz'**
  String get cannotApplyDiscountWithSalePreference;

  /// No description provided for @cannotApplyDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim uygulanamaz'**
  String get cannotApplyDiscount;

  /// No description provided for @cannotSetSalePreferenceInBundle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bir paketteyken toplu indirim ayarlanamaz'**
  String get cannotSetSalePreferenceInBundle;

  /// No description provided for @cannotSetSalePreferenceInCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kampanyadayken toplu indirim ayarlanamaz'**
  String get cannotSetSalePreferenceInCampaign;

  /// No description provided for @maximumProductsPerBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket başına maksimum 6 ürün'**
  String get maximumProductsPerBundle;

  /// No description provided for @selectAtLeastTwoProducts.
  ///
  /// In tr, this message translates to:
  /// **'En az 2 ürün seçin'**
  String get selectAtLeastTwoProducts;

  /// No description provided for @bundlePriceMustBeLessThanTotal.
  ///
  /// In tr, this message translates to:
  /// **'Paket fiyatı toplam orijinal fiyattan düşük olmalıdır'**
  String get bundlePriceMustBeLessThanTotal;

  /// No description provided for @failedToCreateBundleWithError.
  ///
  /// In tr, this message translates to:
  /// **'Paket oluşturulamadı: {error}'**
  String failedToCreateBundleWithError(String error);

  /// No description provided for @noProductsAvailableForBundle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bulunmuyor'**
  String get noProductsAvailableForBundle;

  /// No description provided for @addProductsToShopToCreateBundles.
  ///
  /// In tr, this message translates to:
  /// **'Paket oluşturmak için mağazanıza ürün ekleyin'**
  String get addProductsToShopToCreateBundles;

  /// No description provided for @originalTotal.
  ///
  /// In tr, this message translates to:
  /// **'Orijinal Toplam'**
  String get originalTotal;

  /// No description provided for @saveBundleAmount.
  ///
  /// In tr, this message translates to:
  /// **'{amount} {currency} Tasarruf Edin ({percentage}%)'**
  String saveBundleAmount(String amount, String currency, String percentage);

  /// No description provided for @productsSelectedOutOfSix.
  ///
  /// In tr, this message translates to:
  /// **'{count}/6 ürün seçildi'**
  String productsSelectedOutOfSix(int count);

  /// No description provided for @createBundleWithCount.
  ///
  /// In tr, this message translates to:
  /// **'Paket Oluştur ({count} ürün)'**
  String createBundleWithCount(int count);

  /// No description provided for @productCountBundle.
  ///
  /// In tr, this message translates to:
  /// **'{count} Ürün Paketi'**
  String productCountBundle(int count);

  /// No description provided for @productsColon.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler:'**
  String get productsColon;

  /// No description provided for @bundleHasLessThanTwoValidProducts.
  ///
  /// In tr, this message translates to:
  /// **'Pakette 2\'den az geçerli ürün var'**
  String get bundleHasLessThanTwoValidProducts;

  /// No description provided for @failedToLoadBundleData.
  ///
  /// In tr, this message translates to:
  /// **'Paket verisi yüklenemedi: {error}'**
  String failedToLoadBundleData(String error);

  /// No description provided for @failedToCleanupInvalidProducts.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz ürünler temizlenemedi: {error}'**
  String failedToCleanupInvalidProducts(String error);

  /// No description provided for @bundleMustHaveAtLeastTwoProducts.
  ///
  /// In tr, this message translates to:
  /// **'Pakette en az 2 ürün olmalıdır'**
  String get bundleMustHaveAtLeastTwoProducts;

  /// No description provided for @bundleInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Paket Geçersiz'**
  String get bundleInvalid;

  /// No description provided for @productsInBundle.
  ///
  /// In tr, this message translates to:
  /// **'Paketteki {count} Ürün'**
  String productsInBundle(int count);

  /// No description provided for @invalidProductsRemovedAutomatically.
  ///
  /// In tr, this message translates to:
  /// **'{count} geçersiz ürün otomatik olarak kaldırıldı'**
  String invalidProductsRemovedAutomatically(int count);

  /// No description provided for @currentProductsCount.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut ({count})'**
  String currentProductsCount(int count);

  /// No description provided for @bundle.
  ///
  /// In tr, this message translates to:
  /// **'Paket'**
  String get bundle;

  /// No description provided for @noValidItemsToCheckout.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme için geçerli öğe bulunmamaktadır'**
  String get noValidItemsToCheckout;

  /// No description provided for @validationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama başarısız oldu. Lütfen tekrar deneyin.'**
  String get validationFailed;

  /// No description provided for @validating.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulanıyor...'**
  String get validating;

  /// No description provided for @originalPrice2.
  ///
  /// In tr, this message translates to:
  /// **'Orijinal Fiyat'**
  String get originalPrice2;

  /// No description provided for @selectThisPoint.
  ///
  /// In tr, this message translates to:
  /// **'Bu Noktayı Seç'**
  String get selectThisPoint;

  /// No description provided for @pickupPoints.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktaları'**
  String get pickupPoints;

  /// No description provided for @pickupPointsMap.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktaları Haritası'**
  String get pickupPointsMap;

  /// No description provided for @pickupPointsAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Gel Al Noktaları'**
  String get pickupPointsAvailable;

  /// No description provided for @tapMarkerForDetails.
  ///
  /// In tr, this message translates to:
  /// **'Detaylar için işaretçilere dokunun'**
  String get tapMarkerForDetails;

  /// No description provided for @allPickupPoints.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Gel Al Noktaları'**
  String get allPickupPoints;

  /// No description provided for @enterValidNumber.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir sayı girin'**
  String get enterValidNumber;

  /// No description provided for @forSaleDescription.
  ///
  /// In tr, this message translates to:
  /// **'Arabanızı satmak mı yoksa kiralamak mı istediğinizi seçin.'**
  String get forSaleDescription;

  /// No description provided for @forRentDescription.
  ///
  /// In tr, this message translates to:
  /// **'Arabanızı satmak mı yoksa kiralamak mı istediğinizi seçin.'**
  String get forRentDescription;

  /// No description provided for @currencyDescription.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat için para birimini seçin.'**
  String get currencyDescription;

  /// No description provided for @selectOption.
  ///
  /// In tr, this message translates to:
  /// **'{option} Seçin'**
  String selectOption(String option);

  /// No description provided for @clothingGenderMan.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get clothingGenderMan;

  /// No description provided for @clothingGenderUnisex.
  ///
  /// In tr, this message translates to:
  /// **'Unisex'**
  String get clothingGenderUnisex;

  /// No description provided for @qrLoginFailed.
  ///
  /// In tr, this message translates to:
  /// **'QR giriş başarısız'**
  String get qrLoginFailed;

  /// No description provided for @scanQrCode.
  ///
  /// In tr, this message translates to:
  /// **'QR Kod tara'**
  String get scanQrCode;

  /// No description provided for @clothingSize5XL.
  ///
  /// In tr, this message translates to:
  /// **'5XL'**
  String get clothingSize5XL;

  /// No description provided for @clothingSize4XL.
  ///
  /// In tr, this message translates to:
  /// **'4XL'**
  String get clothingSize4XL;

  /// No description provided for @clothingSize3XL.
  ///
  /// In tr, this message translates to:
  /// **'3XL'**
  String get clothingSize3XL;

  /// No description provided for @clothingSize2XL.
  ///
  /// In tr, this message translates to:
  /// **'2XL'**
  String get clothingSize2XL;

  /// No description provided for @clothingSizeXL.
  ///
  /// In tr, this message translates to:
  /// **'XL'**
  String get clothingSizeXL;

  /// No description provided for @clothingSizeL.
  ///
  /// In tr, this message translates to:
  /// **'L'**
  String get clothingSizeL;

  /// No description provided for @clothingSizeM.
  ///
  /// In tr, this message translates to:
  /// **'M'**
  String get clothingSizeM;

  /// No description provided for @clothingSizeS.
  ///
  /// In tr, this message translates to:
  /// **'S'**
  String get clothingSizeS;

  /// No description provided for @clothingSizeXS.
  ///
  /// In tr, this message translates to:
  /// **'XS'**
  String get clothingSizeXS;

  /// No description provided for @clothingSize2XS.
  ///
  /// In tr, this message translates to:
  /// **'2XS'**
  String get clothingSize2XS;

  /// No description provided for @clothingSize.
  ///
  /// In tr, this message translates to:
  /// **'Beden'**
  String get clothingSize;

  /// No description provided for @clothingFit.
  ///
  /// In tr, this message translates to:
  /// **'Kesim'**
  String get clothingFit;

  /// No description provided for @clothingGender.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet'**
  String get clothingGender;

  /// No description provided for @clothingFitSlim.
  ///
  /// In tr, this message translates to:
  /// **'Dar'**
  String get clothingFitSlim;

  /// No description provided for @clothingFitRegular.
  ///
  /// In tr, this message translates to:
  /// **'Normal'**
  String get clothingFitRegular;

  /// No description provided for @clothingFitRelaxed.
  ///
  /// In tr, this message translates to:
  /// **'Relaxed Fit'**
  String get clothingFitRelaxed;

  /// No description provided for @clothingFitOversize.
  ///
  /// In tr, this message translates to:
  /// **'Oversize Fit'**
  String get clothingFitOversize;

  /// No description provided for @clothingFitTailored.
  ///
  /// In tr, this message translates to:
  /// **'Tailored Fit'**
  String get clothingFitTailored;

  /// No description provided for @clothingType.
  ///
  /// In tr, this message translates to:
  /// **'Malzeme'**
  String get clothingType;

  /// No description provided for @clothingTypeCotton.
  ///
  /// In tr, this message translates to:
  /// **'Pamuk'**
  String get clothingTypeCotton;

  /// No description provided for @clothingTypePolyester.
  ///
  /// In tr, this message translates to:
  /// **'Polyester'**
  String get clothingTypePolyester;

  /// No description provided for @clothingTypeSilk.
  ///
  /// In tr, this message translates to:
  /// **'İpek'**
  String get clothingTypeSilk;

  /// No description provided for @clothingTypeLinen.
  ///
  /// In tr, this message translates to:
  /// **'Keten'**
  String get clothingTypeLinen;

  /// No description provided for @clothingTypeDenim.
  ///
  /// In tr, this message translates to:
  /// **'Denim'**
  String get clothingTypeDenim;

  /// No description provided for @clothingTypeLycra.
  ///
  /// In tr, this message translates to:
  /// **'Lycra'**
  String get clothingTypeLycra;

  /// No description provided for @clothingTypeNylon.
  ///
  /// In tr, this message translates to:
  /// **'Naylon'**
  String get clothingTypeNylon;

  /// No description provided for @clothingTypeBambooFabric.
  ///
  /// In tr, this message translates to:
  /// **'Bambu Kumaş'**
  String get clothingTypeBambooFabric;

  /// No description provided for @deliveryOption1.
  ///
  /// In tr, this message translates to:
  /// **'Gel Al Noktası'**
  String get deliveryOption1;

  /// No description provided for @deliveryText1.
  ///
  /// In tr, this message translates to:
  /// **'Gel-al noktasına özel indirimli kargo'**
  String get deliveryText1;

  /// No description provided for @deliveryOption2.
  ///
  /// In tr, this message translates to:
  /// **'Express Kargo'**
  String get deliveryOption2;

  /// No description provided for @deliveryText2.
  ///
  /// In tr, this message translates to:
  /// **'1 iş günü içerisinde'**
  String get deliveryText2;

  /// No description provided for @deliveryOption3.
  ///
  /// In tr, this message translates to:
  /// **'Normal Kargo'**
  String get deliveryOption3;

  /// No description provided for @subtotal.
  ///
  /// In tr, this message translates to:
  /// **'Ara Toplam'**
  String get subtotal;

  /// No description provided for @priceSummary.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Özeti'**
  String get priceSummary;

  /// No description provided for @deliveryText3.
  ///
  /// In tr, this message translates to:
  /// **'1-3 iş günü içerisinde'**
  String get deliveryText3;

  /// No description provided for @orderInformation.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Bilgileri'**
  String get orderInformation;

  /// No description provided for @purchasedItems.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alınan Ürünler'**
  String get purchasedItems;

  /// No description provided for @myReceipts.
  ///
  /// In tr, this message translates to:
  /// **'Faturalarım'**
  String get myReceipts;

  /// No description provided for @clothingTypeChiffon.
  ///
  /// In tr, this message translates to:
  /// **'Şifon'**
  String get clothingTypeChiffon;

  /// No description provided for @clothingTypeJerseyKnit.
  ///
  /// In tr, this message translates to:
  /// **'Jersey Örgü'**
  String get clothingTypeJerseyKnit;

  /// No description provided for @clothingTypeCashmere.
  ///
  /// In tr, this message translates to:
  /// **'Kaşmir'**
  String get clothingTypeCashmere;

  /// No description provided for @googleLoginButton.
  ///
  /// In tr, this message translates to:
  /// **'Google ile Giriş Yap'**
  String get googleLoginButton;

  /// No description provided for @outOfStockTitle.
  ///
  /// In tr, this message translates to:
  /// **'Stok Dışı'**
  String get outOfStockTitle;

  /// No description provided for @outOfStockMessage.
  ///
  /// In tr, this message translates to:
  /// **'{productNames} stokta kalmadı. Devam etmek istiyor musunuz?'**
  String outOfStockMessage(Object productNames);

  /// No description provided for @imageContainsInappropriateContent.
  ///
  /// In tr, this message translates to:
  /// **'Görselde uygunsuz içerik tespit edildi'**
  String get imageContainsInappropriateContent;

  /// No description provided for @youNeedToLoginToTrackYourProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünleriniz takip etmek için giriş yapın'**
  String get youNeedToLoginToTrackYourProducts;

  /// No description provided for @clothingDetails.
  ///
  /// In tr, this message translates to:
  /// **'Giyim detayları'**
  String get clothingDetails;

  /// No description provided for @colorImages.
  ///
  /// In tr, this message translates to:
  /// **'Renk seçenekleri'**
  String get colorImages;

  /// No description provided for @emailVerified.
  ///
  /// In tr, this message translates to:
  /// **'E-posta başarıyla doğrulandı!'**
  String get emailVerified;

  /// No description provided for @checkSpamFolder.
  ///
  /// In tr, this message translates to:
  /// **'E-postayı bulamıyor musunuz? Spam klasörünüzü kontrol edin.'**
  String get checkSpamFolder;

  /// No description provided for @profileCompletionInfo.
  ///
  /// In tr, this message translates to:
  /// **'Profilinizi tamamlayın'**
  String get profileCompletionInfo;

  /// No description provided for @profileCompleted.
  ///
  /// In tr, this message translates to:
  /// **'Profil başarıyla tamamlandı!'**
  String get profileCompleted;

  /// No description provided for @joinUsToday.
  ///
  /// In tr, this message translates to:
  /// **'Dilediğiniz herşeyi bulmak için bugün bize katılın!'**
  String get joinUsToday;

  /// No description provided for @optional.
  ///
  /// In tr, this message translates to:
  /// **'İsteğe bağlı'**
  String get optional;

  /// No description provided for @or.
  ///
  /// In tr, this message translates to:
  /// **'VEYA'**
  String get or;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In tr, this message translates to:
  /// **'Zaten hesabınız var mı? Giriş yapın'**
  String get alreadyHaveAccount;

  /// No description provided for @signUp.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt Ol'**
  String get signUp;

  /// No description provided for @dontHaveAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınız yok mu? '**
  String get dontHaveAccount;

  /// No description provided for @emailSentTo.
  ///
  /// In tr, this message translates to:
  /// **'E-posta gönderildi:'**
  String get emailSentTo;

  /// No description provided for @boughtThisProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü satın aldı'**
  String get boughtThisProduct;

  /// No description provided for @loginToUpdateYourProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilinizi düzenlemek için giriş yapın'**
  String get loginToUpdateYourProfile;

  /// No description provided for @earnPointsShort.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş yaparken puan kazanın'**
  String get earnPointsShort;

  /// No description provided for @earnPointsModalText.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş yaparken puan kazanın ve arkadaşlarınızı birlikte kazanmaya davet edin!'**
  String get earnPointsModalText;

  /// No description provided for @searchResultsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} arama sonucu'**
  String searchResultsCount(Object count);

  /// No description provided for @reports.
  ///
  /// In tr, this message translates to:
  /// **'Raporlar'**
  String get reports;

  /// No description provided for @createNewReport.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Rapor Oluştur'**
  String get createNewReport;

  /// No description provided for @generateCustomReportsForYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanız için özel raporlar oluşturun'**
  String get generateCustomReportsForYourShop;

  /// No description provided for @reportName.
  ///
  /// In tr, this message translates to:
  /// **'Rapor Adı'**
  String get reportName;

  /// No description provided for @enterReportName.
  ///
  /// In tr, this message translates to:
  /// **'Rapor adını girin...'**
  String get enterReportName;

  /// No description provided for @selectDataToInclude.
  ///
  /// In tr, this message translates to:
  /// **'Dahil Edilecek Verileri Seçin'**
  String get selectDataToInclude;

  /// No description provided for @includeProductInformation.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bilgilerini dahil et'**
  String get includeProductInformation;

  /// No description provided for @orders.
  ///
  /// In tr, this message translates to:
  /// **'Siparişler'**
  String get orders;

  /// No description provided for @includeOrderInformation.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş bilgilerini dahil et'**
  String get includeOrderInformation;

  /// No description provided for @boostHistory.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkarma Geçmişi'**
  String get boostHistory;

  /// No description provided for @includeBoostInformation.
  ///
  /// In tr, this message translates to:
  /// **'Ürün öne çıkarma bilgilerini dahil et'**
  String get includeBoostInformation;

  /// No description provided for @generateReport.
  ///
  /// In tr, this message translates to:
  /// **'Rapor Oluştur'**
  String get generateReport;

  /// No description provided for @existingReports.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Raporlar'**
  String get existingReports;

  /// No description provided for @noReportsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz Rapor Yok'**
  String get noReportsYet;

  /// No description provided for @createYourFirstReport.
  ///
  /// In tr, this message translates to:
  /// **'Başlamak için ilk raporunuzu oluşturun'**
  String get createYourFirstReport;

  /// No description provided for @selectDateRange.
  ///
  /// In tr, this message translates to:
  /// **'Tarih aralığı seçin...'**
  String get selectDateRange;

  /// No description provided for @pleaseEnterReportName.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir rapor adı girin'**
  String get pleaseEnterReportName;

  /// No description provided for @pleaseSelectAtLeastOneDataType.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen dahil edilecek en az bir veri türü seçin'**
  String get pleaseSelectAtLeastOneDataType;

  /// No description provided for @reportGeneratedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Rapor başarıyla oluşturuldu!'**
  String get reportGeneratedSuccessfully;

  /// No description provided for @removeFromCampaignTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyadan Çıkar'**
  String get removeFromCampaignTitle;

  /// No description provided for @productInCampaignMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün şu anda {campaignName} kampanyasında.'**
  String productInCampaignMessage(Object campaignName);

  /// No description provided for @removeFromCampaignAndDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyadan ve indirimden çıkar'**
  String get removeFromCampaignAndDiscount;

  /// No description provided for @removingFromCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Kampanyadan çıkarılıyor...'**
  String get removingFromCampaign;

  /// No description provided for @removedFromCampaignAndDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kampanyadan çıkarıldı ve indirim kaldırıldı'**
  String get removedFromCampaignAndDiscount;

  /// No description provided for @reportDownloadedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Rapor başarıyla indirildi!'**
  String get reportDownloadedSuccessfully;

  /// No description provided for @sortOptions.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama Seçenekleri'**
  String get sortOptions;

  /// No description provided for @sortByDate.
  ///
  /// In tr, this message translates to:
  /// **'Tarih'**
  String get sortByDate;

  /// No description provided for @sortByPurchaseCount.
  ///
  /// In tr, this message translates to:
  /// **'Satış Sayısı'**
  String get sortByPurchaseCount;

  /// No description provided for @sortByClickCount.
  ///
  /// In tr, this message translates to:
  /// **'Tıklanma Sayısı'**
  String get sortByClickCount;

  /// No description provided for @sortByFavoritesCount.
  ///
  /// In tr, this message translates to:
  /// **'Favori Sayısı'**
  String get sortByFavoritesCount;

  /// No description provided for @sortByCartCount.
  ///
  /// In tr, this message translates to:
  /// **'Sepet Sayısı'**
  String get sortByCartCount;

  /// No description provided for @sortByPrice.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat'**
  String get sortByPrice;

  /// No description provided for @sortByDuration.
  ///
  /// In tr, this message translates to:
  /// **'Süre'**
  String get sortByDuration;

  /// No description provided for @sortByImpressionCount.
  ///
  /// In tr, this message translates to:
  /// **'Görüntülenme Sayısı'**
  String get sortByImpressionCount;

  /// No description provided for @sortOrder.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama Düzeni'**
  String get sortOrder;

  /// No description provided for @descending.
  ///
  /// In tr, this message translates to:
  /// **'Azalan'**
  String get descending;

  /// No description provided for @ascending.
  ///
  /// In tr, this message translates to:
  /// **'Artan'**
  String get ascending;

  /// No description provided for @selectSortBy.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama Seç'**
  String get selectSortBy;

  /// No description provided for @sortedBy.
  ///
  /// In tr, this message translates to:
  /// **'Sıralandı'**
  String get sortedBy;

  /// No description provided for @favorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler'**
  String get favorites;

  /// No description provided for @cartAdds.
  ///
  /// In tr, this message translates to:
  /// **'Sepet Eklemeleri'**
  String get cartAdds;

  /// No description provided for @reportContents.
  ///
  /// In tr, this message translates to:
  /// **'Rapor İçeriği'**
  String get reportContents;

  /// No description provided for @generated.
  ///
  /// In tr, this message translates to:
  /// **'Oluşturulma'**
  String get generated;

  /// No description provided for @productName.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Adı'**
  String get productName;

  /// No description provided for @sales.
  ///
  /// In tr, this message translates to:
  /// **'Satış'**
  String get sales;

  /// No description provided for @product.
  ///
  /// In tr, this message translates to:
  /// **'Ürün'**
  String get product;

  /// No description provided for @item.
  ///
  /// In tr, this message translates to:
  /// **'Öğe'**
  String get item;

  /// No description provided for @durationMinutes.
  ///
  /// In tr, this message translates to:
  /// **'Süre (dk)'**
  String get durationMinutes;

  /// No description provided for @cost.
  ///
  /// In tr, this message translates to:
  /// **'Maliyet'**
  String get cost;

  /// No description provided for @impressions.
  ///
  /// In tr, this message translates to:
  /// **'Gösterimler'**
  String get impressions;

  /// No description provided for @clicks.
  ///
  /// In tr, this message translates to:
  /// **'Tıklamalar'**
  String get clicks;

  /// No description provided for @notSpecified.
  ///
  /// In tr, this message translates to:
  /// **'Belirtilmemiş'**
  String get notSpecified;

  /// No description provided for @unknownShop.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Mağaza'**
  String get unknownShop;

  /// No description provided for @statusProcessing.
  ///
  /// In tr, this message translates to:
  /// **'İşleniyor'**
  String get statusProcessing;

  /// No description provided for @statusReturned.
  ///
  /// In tr, this message translates to:
  /// **'İade Edildi'**
  String get statusReturned;

  /// No description provided for @showingFirstItemsOfTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam {totalCount} öğeden ilk {firstCount} tanesi gösteriliyor'**
  String showingFirstItemsOfTotal(int firstCount, int totalCount);

  /// No description provided for @noDataAvailableForSection.
  ///
  /// In tr, this message translates to:
  /// **'Bu bölüm için mevcut veri bulunmuyor'**
  String get noDataAvailableForSection;

  /// No description provided for @cartCount.
  ///
  /// In tr, this message translates to:
  /// **'Sepet'**
  String get cartCount;

  /// No description provided for @generatingReport.
  ///
  /// In tr, this message translates to:
  /// **'Rapor Oluşturuluyor...'**
  String get generatingReport;

  /// No description provided for @pleaseWaitWhileWeGenerateYourReport.
  ///
  /// In tr, this message translates to:
  /// **'Raporunuz oluşturulurken lütfen bekleyin'**
  String get pleaseWaitWhileWeGenerateYourReport;

  /// No description provided for @productFilters.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Filtreleri'**
  String get productFilters;

  /// No description provided for @subsubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Alt-alt kategori'**
  String get subsubcategory;

  /// No description provided for @allItems.
  ///
  /// In tr, this message translates to:
  /// **'Tüm {items}'**
  String allItems(String items);

  /// No description provided for @clearFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri Temizle'**
  String get clearFilters;

  /// No description provided for @selectCategory.
  ///
  /// In tr, this message translates to:
  /// **'Kategori seçin'**
  String get selectCategory;

  /// No description provided for @selectSubSubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Alt-Alt Kategori Seç'**
  String get selectSubSubcategory;

  /// No description provided for @allCategories.
  ///
  /// In tr, this message translates to:
  /// **'Tüm Kategoriler'**
  String get allCategories;

  /// No description provided for @skipSubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Atla - Kategorideki Tüm Ürünleri Göster'**
  String get skipSubcategory;

  /// No description provided for @skipSubSubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Atla - Alt Kategorideki Tüm Ürünleri Göster'**
  String get skipSubSubcategory;

  /// No description provided for @invite.
  ///
  /// In tr, this message translates to:
  /// **'Davet Et'**
  String get invite;

  /// No description provided for @referralCode.
  ///
  /// In tr, this message translates to:
  /// **'Davet Kodu (Opsiyonel)'**
  String get referralCode;

  /// No description provided for @proceed.
  ///
  /// In tr, this message translates to:
  /// **'İlerle'**
  String get proceed;

  /// No description provided for @inviteFriends.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla kazanmak için arkadaşlarını davet et'**
  String get inviteFriends;

  /// No description provided for @playPointsTitle.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoints'**
  String get playPointsTitle;

  /// No description provided for @yourReferralCode.
  ///
  /// In tr, this message translates to:
  /// **'Referans Kodunuz'**
  String get yourReferralCode;

  /// No description provided for @copyTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Kodu kopyala'**
  String get copyTooltip;

  /// No description provided for @shareTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Kodu paylaş'**
  String get shareTooltip;

  /// No description provided for @invitedUsers.
  ///
  /// In tr, this message translates to:
  /// **'Davet Edilen Kullanıcılar'**
  String get invitedUsers;

  /// No description provided for @goToTeras.
  ///
  /// In tr, this message translates to:
  /// **'Teras\'a Git'**
  String get goToTeras;

  /// No description provided for @referralCopied.
  ///
  /// In tr, this message translates to:
  /// **'Referans kodu kopyalandı!'**
  String get referralCopied;

  /// No description provided for @noReferrals.
  ///
  /// In tr, this message translates to:
  /// **'Henüz davet yok.'**
  String get noReferrals;

  /// No description provided for @joined.
  ///
  /// In tr, this message translates to:
  /// **'Katıldı: {date}'**
  String joined(Object date);

  /// No description provided for @userDataNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı verisi bulunamadı.'**
  String get userDataNotFound;

  /// No description provided for @usersAlsoBought.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar bu ürünleride satın aldı'**
  String get usersAlsoBought;

  /// No description provided for @spendPoints.
  ///
  /// In tr, this message translates to:
  /// **'Ürün satın almak için puanlarını harca!'**
  String get spendPoints;

  /// No description provided for @refresh.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get refresh;

  /// No description provided for @addFavoriteShops.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanı favorilere ekle'**
  String get addFavoriteShops;

  /// No description provided for @noAccountText.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınız yok mu? Kayıt olun!'**
  String get noAccountText;

  /// No description provided for @guestContinueText.
  ///
  /// In tr, this message translates to:
  /// **'Ziyaretçi olarak devam et'**
  String get guestContinueText;

  /// No description provided for @emailErrorEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir e-posta girin'**
  String get emailErrorEmpty;

  /// No description provided for @emailErrorInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir e-posta girin'**
  String get emailErrorInvalid;

  /// No description provided for @discoverShops.
  ///
  /// In tr, this message translates to:
  /// **'Henüz favori dükkanınız bulunmamaktadır'**
  String get discoverShops;

  /// No description provided for @passwordErrorEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir şifre girin'**
  String get passwordErrorEmpty;

  /// No description provided for @passwordErrorShort.
  ///
  /// In tr, this message translates to:
  /// **'Şifre en az 6 karakter olmalıdır'**
  String get passwordErrorShort;

  /// No description provided for @errorUserNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta ile kayıtlı bir kullanıcı bulunamadı.'**
  String get errorUserNotFound;

  /// No description provided for @shopDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan başarıyla silindi'**
  String get shopDeletedSuccessfully;

  /// No description provided for @errorDeletingShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan silinemedi'**
  String get errorDeletingShop;

  /// No description provided for @errorTogglingFavorite.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan favorilere eklenemedi'**
  String get errorTogglingFavorite;

  /// No description provided for @discoverProducts.
  ///
  /// In tr, this message translates to:
  /// **'Geniş ürün yelpazesini keşfedin ve favorilerinizi ekleyin!'**
  String get discoverProducts;

  /// No description provided for @discoverVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Geniş araç yelpazesini keşfedin ve favorilerinize ekleyin!'**
  String get discoverVehicles;

  /// No description provided for @discoverPropertiesPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Geniş bir mülk yelpazesini keşfedin ve favorilerinize ekleyin!'**
  String get discoverPropertiesPlaceholder;

  /// No description provided for @addShops.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan ekle'**
  String get addShops;

  /// No description provided for @selectMainRegion.
  ///
  /// In tr, this message translates to:
  /// **'İlçe Seçin'**
  String get selectMainRegion;

  /// No description provided for @selectSubregion.
  ///
  /// In tr, this message translates to:
  /// **'Bölge Seçin'**
  String get selectSubregion;

  /// No description provided for @mainRegion.
  ///
  /// In tr, this message translates to:
  /// **'İlçe'**
  String get mainRegion;

  /// No description provided for @searchCategoriesError.
  ///
  /// In tr, this message translates to:
  /// **'Kategori bulunamadı'**
  String get searchCategoriesError;

  /// No description provided for @emptyCartPlaceholderText.
  ///
  /// In tr, this message translates to:
  /// **'Geniş ürün yelpazesini keşfedin ve favorilerinizi sepete ekleyin!'**
  String get emptyCartPlaceholderText;

  /// No description provided for @discover.
  ///
  /// In tr, this message translates to:
  /// **'Keşfet'**
  String get discover;

  /// No description provided for @shopRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan kaldırıldı'**
  String get shopRemoved;

  /// No description provided for @inappropriateContentDetected.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz içerik tespit edildi'**
  String get inappropriateContentDetected;

  /// No description provided for @errorCreatingNotification.
  ///
  /// In tr, this message translates to:
  /// **'Bir sorun oluştu'**
  String get errorCreatingNotification;

  /// No description provided for @reviewSubmittedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Başarıyla gönderildi'**
  String get reviewSubmittedSuccessfully;

  /// No description provided for @sendToContact.
  ///
  /// In tr, this message translates to:
  /// **'Bir kişiye gönder'**
  String get sendToContact;

  /// No description provided for @sendViaAnotherApp.
  ///
  /// In tr, this message translates to:
  /// **'Başka bir uygulama ile gönder'**
  String get sendViaAnotherApp;

  /// No description provided for @errorFetchingContacts.
  ///
  /// In tr, this message translates to:
  /// **'Kişiler alınırken hata oluştu.'**
  String get errorFetchingContacts;

  /// No description provided for @sellerReview2.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı yorumu'**
  String get sellerReview2;

  /// No description provided for @sellerReview3.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Değerlendirmesi'**
  String get sellerReview3;

  /// No description provided for @noContactsFound.
  ///
  /// In tr, this message translates to:
  /// **'Hiç kişi bulunamadı.'**
  String get noContactsFound;

  /// No description provided for @errorLoadingContact.
  ///
  /// In tr, this message translates to:
  /// **'Kişi yüklenirken hata oluştu.'**
  String get errorLoadingContact;

  /// No description provided for @contactNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kişi bulunamadı.'**
  String get contactNotFound;

  /// No description provided for @productSharedWithContact.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla paylaşıldı!'**
  String get productSharedWithContact;

  /// No description provided for @chats.
  ///
  /// In tr, this message translates to:
  /// **'Mesajlar'**
  String get chats;

  /// No description provided for @contacts.
  ///
  /// In tr, this message translates to:
  /// **'Kişiler'**
  String get contacts;

  /// No description provided for @errorWrongPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifre yanlış.'**
  String get errorWrongPassword;

  /// No description provided for @errorInvalidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz e-posta adresi.'**
  String get errorInvalidEmail;

  /// No description provided for @noMoreProductsToAdd.
  ///
  /// In tr, this message translates to:
  /// **'Eklenecek ürün kalmadı'**
  String get noMoreProductsToAdd;

  /// No description provided for @addVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video ekle'**
  String get addVideo;

  /// No description provided for @errorGeneral.
  ///
  /// In tr, this message translates to:
  /// **'Giriş başarısız. Lütfen tekrar deneyin.'**
  String get errorGeneral;

  /// No description provided for @vehicle.
  ///
  /// In tr, this message translates to:
  /// **'Araç'**
  String get vehicle;

  /// No description provided for @selectLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil Seçin'**
  String get selectLanguage;

  /// No description provided for @english.
  ///
  /// In tr, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @turkish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get turkish;

  /// No description provided for @russian.
  ///
  /// In tr, this message translates to:
  /// **'Русский'**
  String get russian;

  /// No description provided for @homeScreenTitle.
  ///
  /// In tr, this message translates to:
  /// **'Anasayfa'**
  String get homeScreenTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settingsTitle;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil Seçin'**
  String get settingsLanguage;

  /// No description provided for @homeScreenSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Gayrimenkul Uygulamasına Hoş Geldiniz.'**
  String get homeScreenSubtitle;

  /// No description provided for @propertyListingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Listeleri'**
  String get propertyListingsTitle;

  /// No description provided for @propertyListingsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Tüm gayrimenkulleri görüntüleyin'**
  String get propertyListingsDescription;

  /// No description provided for @propertyValuationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Değer Biçme'**
  String get propertyValuationTitle;

  /// No description provided for @propertyValuationDescription.
  ///
  /// In tr, this message translates to:
  /// **'Emlak değerini öğrenin'**
  String get propertyValuationDescription;

  /// No description provided for @rentalManagementTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kira Yönetim Sistemi'**
  String get rentalManagementTitle;

  /// No description provided for @rentalManagementDescription.
  ///
  /// In tr, this message translates to:
  /// **'Kira yönetim araçlarını kullanın'**
  String get rentalManagementDescription;

  /// No description provided for @viewButton.
  ///
  /// In tr, this message translates to:
  /// **'Görüntüle'**
  String get viewButton;

  /// No description provided for @notifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim'**
  String get notifications;

  /// No description provided for @profile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @realEstateListings.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Listeleri'**
  String get realEstateListings;

  /// No description provided for @propertyValuation.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Değer Biçme'**
  String get propertyValuation;

  /// No description provided for @rentalManagementSystem.
  ///
  /// In tr, this message translates to:
  /// **'Kira Yönetim Sistemi'**
  String get rentalManagementSystem;

  /// No description provided for @view.
  ///
  /// In tr, this message translates to:
  /// **'Görüntüle'**
  String get view;

  /// No description provided for @useRentalManagementTools.
  ///
  /// In tr, this message translates to:
  /// **'Kira yönetim araçlarını kullanın'**
  String get useRentalManagementTools;

  /// No description provided for @learnPropertyValuation.
  ///
  /// In tr, this message translates to:
  /// **'Emlak değerini öğrenin'**
  String get learnPropertyValuation;

  /// No description provided for @viewAllProperties.
  ///
  /// In tr, this message translates to:
  /// **'Tüm gayrimenkulleri görüntüleyin'**
  String get viewAllProperties;

  /// No description provided for @noEmail.
  ///
  /// In tr, this message translates to:
  /// **'Email Yok'**
  String get noEmail;

  /// No description provided for @noLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konum Yok'**
  String get noLocation;

  /// No description provided for @bedroomsIcon.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Odası'**
  String get bedroomsIcon;

  /// No description provided for @bathroomsIcon.
  ///
  /// In tr, this message translates to:
  /// **'Banyo'**
  String get bathroomsIcon;

  /// No description provided for @houseSizeIcon.
  ///
  /// In tr, this message translates to:
  /// **'Ev Büyüklüğü'**
  String get houseSizeIcon;

  /// No description provided for @featured.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkan'**
  String get featured;

  /// No description provided for @myProperties.
  ///
  /// In tr, this message translates to:
  /// **'Mülklerim'**
  String get myProperties;

  /// No description provided for @email.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get email;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get password;

  /// No description provided for @planLimitReached.
  ///
  /// In tr, this message translates to:
  /// **'Plan Limitiniz Doldu'**
  String get planLimitReached;

  /// No description provided for @planLimitReachedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Plan limitinizi doldurdunuz. Daha fazla ilan eklemek için planınızı yükseltin.'**
  String get planLimitReachedMessage;

  /// No description provided for @upgrade.
  ///
  /// In tr, this message translates to:
  /// **'Yükselt'**
  String get upgrade;

  /// No description provided for @search.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In tr, this message translates to:
  /// **'Filtre'**
  String get filter;

  /// No description provided for @resetSearch.
  ///
  /// In tr, this message translates to:
  /// **'Aramayı Sıfırla'**
  String get resetSearch;

  /// No description provided for @listings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlar'**
  String get listings;

  /// No description provided for @home.
  ///
  /// In tr, this message translates to:
  /// **'Nar24'**
  String get home;

  /// No description provided for @auction.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırma'**
  String get auction;

  /// No description provided for @trendingItems.
  ///
  /// In tr, this message translates to:
  /// **'Trend Ürünler'**
  String get trendingItems;

  /// No description provided for @featuredShops.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkan Mağazalar'**
  String get featuredShops;

  /// No description provided for @companies.
  ///
  /// In tr, this message translates to:
  /// **'Kuruluşlar'**
  String get companies;

  /// No description provided for @agencies.
  ///
  /// In tr, this message translates to:
  /// **'Acenteler'**
  String get agencies;

  /// No description provided for @myProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilim'**
  String get myProfile;

  /// No description provided for @logout.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış Yap'**
  String get logout;

  /// No description provided for @list.
  ///
  /// In tr, this message translates to:
  /// **'Listele'**
  String get list;

  /// No description provided for @inbox.
  ///
  /// In tr, this message translates to:
  /// **'Gelen Kutusu'**
  String get inbox;

  /// No description provided for @region.
  ///
  /// In tr, this message translates to:
  /// **'Bölge'**
  String get region;

  /// No description provided for @landSize.
  ///
  /// In tr, this message translates to:
  /// **'Arazi Büyüklüğü'**
  String get landSize;

  /// No description provided for @houseSize.
  ///
  /// In tr, this message translates to:
  /// **'Ev Büyüklüğü'**
  String get houseSize;

  /// No description provided for @bedrooms.
  ///
  /// In tr, this message translates to:
  /// **'Yatak Odası'**
  String get bedrooms;

  /// No description provided for @bathrooms.
  ///
  /// In tr, this message translates to:
  /// **'Banyo'**
  String get bathrooms;

  /// No description provided for @garages.
  ///
  /// In tr, this message translates to:
  /// **'Garaj'**
  String get garages;

  /// No description provided for @pool.
  ///
  /// In tr, this message translates to:
  /// **'Havuz'**
  String get pool;

  /// No description provided for @bbq.
  ///
  /// In tr, this message translates to:
  /// **'Barbekü'**
  String get bbq;

  /// No description provided for @outdoorShower.
  ///
  /// In tr, this message translates to:
  /// **'Açık Duş'**
  String get outdoorShower;

  /// No description provided for @outdoorLighting.
  ///
  /// In tr, this message translates to:
  /// **'Dış Aydınlatma'**
  String get outdoorLighting;

  /// No description provided for @terrace.
  ///
  /// In tr, this message translates to:
  /// **'Teras'**
  String get terrace;

  /// No description provided for @gym.
  ///
  /// In tr, this message translates to:
  /// **'Spor Salonu'**
  String get gym;

  /// No description provided for @television.
  ///
  /// In tr, this message translates to:
  /// **'Televizyon'**
  String get television;

  /// No description provided for @whiteGoods.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz Eşya'**
  String get whiteGoods;

  /// No description provided for @markOnMap.
  ///
  /// In tr, this message translates to:
  /// **'Haritada İşaretle'**
  String get markOnMap;

  /// No description provided for @viewonmap.
  ///
  /// In tr, this message translates to:
  /// **'Haritada Görüntüle'**
  String get viewonmap;

  /// No description provided for @selectedLocation.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen Konum'**
  String get selectedLocation;

  /// No description provided for @listProperty.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Listele'**
  String get listProperty;

  /// No description provided for @residential.
  ///
  /// In tr, this message translates to:
  /// **'Konut'**
  String get residential;

  /// No description provided for @land.
  ///
  /// In tr, this message translates to:
  /// **'Arsa'**
  String get land;

  /// No description provided for @noImages.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir mülk fotoğrafı yükleyin.'**
  String get noImages;

  /// No description provided for @propertyListedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Mülk başarıyla listelendi!'**
  String get propertyListedSuccess;

  /// No description provided for @errorOccurredDuringListing.
  ///
  /// In tr, this message translates to:
  /// **'Hata oluştu: '**
  String get errorOccurredDuringListing;

  /// No description provided for @userNotFoundPleaseLogin.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı bulunamadı. Lütfen tekrar giriş yapın.'**
  String get userNotFoundPleaseLogin;

  /// No description provided for @learnPropertyValue.
  ///
  /// In tr, this message translates to:
  /// **'Emlak değerini öğrenin'**
  String get learnPropertyValue;

  /// No description provided for @confirmDeleteProperty.
  ///
  /// In tr, this message translates to:
  /// **'Bu mülkü silmek istediğinizden emin misiniz?'**
  String get confirmDeleteProperty;

  /// No description provided for @twoFactorFailedMessage.
  ///
  /// In tr, this message translates to:
  /// **'İki faktörlü doğrulama başarısız oldu. Lütfen tekrar deneyin.'**
  String get twoFactorFailedMessage;

  /// No description provided for @errorNetwork.
  ///
  /// In tr, this message translates to:
  /// **'Ağ hatası. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.'**
  String get errorNetwork;

  /// No description provided for @errorTooManyAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla başarısız deneme. Lütfen daha sonra tekrar deneyin.'**
  String get errorTooManyAttempts;

  /// No description provided for @errorAccountExists.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta adresiyle farklı bir giriş yöntemi kullanılarak zaten bir hesap oluşturulmuş.'**
  String get errorAccountExists;

  /// No description provided for @twoFactorUseEmailInstead.
  ///
  /// In tr, this message translates to:
  /// **'Kod yerine e-posta yolunu kullanın'**
  String get twoFactorUseEmailInstead;

  /// No description provided for @twoFactorPleaseWait.
  ///
  /// In tr, this message translates to:
  /// **'Yeni bir kod talep etmeden önce lütfen 30 saniye bekleyin.'**
  String get twoFactorPleaseWait;

  /// No description provided for @share.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get share;

  /// No description provided for @boost.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkar'**
  String get boost;

  /// No description provided for @boosted.
  ///
  /// In tr, this message translates to:
  /// **'Öne Çıkarıldı'**
  String get boosted;

  /// No description provided for @days.
  ///
  /// In tr, this message translates to:
  /// **'gün'**
  String get days;

  /// No description provided for @hours.
  ///
  /// In tr, this message translates to:
  /// **'Saat'**
  String get hours;

  /// No description provided for @checkOutThisProperty.
  ///
  /// In tr, this message translates to:
  /// **'Bu mülke bir göz atın: {propertyUrl}'**
  String checkOutThisProperty(Object propertyUrl);

  /// No description provided for @unnamed.
  ///
  /// In tr, this message translates to:
  /// **'İsimsiz'**
  String get unnamed;

  /// No description provided for @propertyDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Mülk başarıyla silindi!'**
  String get propertyDeletedSuccessfully;

  /// No description provided for @noPropertiesAddedYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir mülk yok.'**
  String get noPropertiesAddedYet;

  /// No description provided for @propertyDetailTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Detayları'**
  String get propertyDetailTitle;

  /// No description provided for @notificationDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim silindi.'**
  String get notificationDeletedSuccessfully;

  /// No description provided for @companyInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Şirket bilgisi bulunamadı.'**
  String get companyInfoNotFound;

  /// No description provided for @propertyInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Mülk bilgisi bulunamadı.'**
  String get propertyInfoNotFound;

  /// No description provided for @heightExceedsMaximum.
  ///
  /// In tr, this message translates to:
  /// **'Yükseklik maksimum değeri aşıyor'**
  String get heightExceedsMaximum;

  /// No description provided for @widthExceedsMaximum.
  ///
  /// In tr, this message translates to:
  /// **'Genişlik maksimum değeri aşıyor'**
  String get widthExceedsMaximum;

  /// No description provided for @maximum.
  ///
  /// In tr, this message translates to:
  /// **'Maks'**
  String get maximum;

  /// No description provided for @enterValue.
  ///
  /// In tr, this message translates to:
  /// **'Girin'**
  String get enterValue;

  /// No description provided for @noNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bildirim yok.'**
  String get noNotifications;

  /// No description provided for @confirmDeleteNotification.
  ///
  /// In tr, this message translates to:
  /// **'Bu bildirimi silmek istediğinizden emin misiniz?'**
  String get confirmDeleteNotification;

  /// No description provided for @boostExpiringMessage.
  ///
  /// In tr, this message translates to:
  /// **'Boostlu mülkünüz \"{propertyName}\" 6 saat içinde sona erecek.'**
  String boostExpiringMessage(Object propertyName);

  /// No description provided for @boostFinishedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Boostlu mülkünüz \"{propertyName}\" başarıyla sona erdi.'**
  String boostFinishedMessage(Object propertyName);

  /// No description provided for @notLoggedIn.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yapmadınız.'**
  String get notLoggedIn;

  /// No description provided for @myPropertiesScreenTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mülklerim'**
  String get myPropertiesScreenTitle;

  /// No description provided for @myPropertiesScreenBody.
  ///
  /// In tr, this message translates to:
  /// **'Mülklerim Ekranı'**
  String get myPropertiesScreenBody;

  /// No description provided for @curtainDimensions.
  ///
  /// In tr, this message translates to:
  /// **'Perde Ölçüleri'**
  String get curtainDimensions;

  /// No description provided for @enterCurtainDimensions.
  ///
  /// In tr, this message translates to:
  /// **'Perde Ölçülerini Girin'**
  String get enterCurtainDimensions;

  /// No description provided for @curtainDimensionsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen perdenizin maksimum genişlik ve yüksekliğini metre cinsinden belirtin'**
  String get curtainDimensionsDescription;

  /// No description provided for @maxWidth.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum Genişlik'**
  String get maxWidth;

  /// No description provided for @maxHeight.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum Yükseklik'**
  String get maxHeight;

  /// No description provided for @widthPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'örn., 2.5'**
  String get widthPlaceholder;

  /// No description provided for @heightPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'örn., 2.8'**
  String get heightPlaceholder;

  /// No description provided for @metersUnit.
  ///
  /// In tr, this message translates to:
  /// **'m'**
  String get metersUnit;

  /// No description provided for @widthHint.
  ///
  /// In tr, this message translates to:
  /// **'Perdenizin kaplayabileceği maksimum genişliği girin'**
  String get widthHint;

  /// No description provided for @heightHint.
  ///
  /// In tr, this message translates to:
  /// **'Perdenizin maksimum yüksekliğini (boyunu) girin'**
  String get heightHint;

  /// No description provided for @dimensionsSummary.
  ///
  /// In tr, this message translates to:
  /// **'Perde Ölçüleri'**
  String get dimensionsSummary;

  /// No description provided for @pleaseEnterBothDimensions.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen hem genişlik hem de yükseklik girin'**
  String get pleaseEnterBothDimensions;

  /// No description provided for @pleaseEnterValidWidth.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen 0\'dan büyük geçerli bir genişlik girin'**
  String get pleaseEnterValidWidth;

  /// No description provided for @pleaseEnterValidHeight.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen 0\'dan büyük geçerli bir yükseklik girin'**
  String get pleaseEnterValidHeight;

  /// No description provided for @fantasyWearType.
  ///
  /// In tr, this message translates to:
  /// **'Fantezi Giyim Türü'**
  String get fantasyWearType;

  /// No description provided for @selectFantasyWearType.
  ///
  /// In tr, this message translates to:
  /// **'Fantezi Giyim Türünü Seçin'**
  String get selectFantasyWearType;

  /// No description provided for @fantasyWearDescription.
  ///
  /// In tr, this message translates to:
  /// **'Sattığınız fantezi giyim türünü seçin'**
  String get fantasyWearDescription;

  /// No description provided for @pleaseSelectFantasyWearType.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir fantezi giyim türü seçin'**
  String get pleaseSelectFantasyWearType;

  /// No description provided for @selectedType.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen Tür'**
  String get selectedType;

  /// No description provided for @fantasyWearLingerie.
  ///
  /// In tr, this message translates to:
  /// **'İç Çamaşırı'**
  String get fantasyWearLingerie;

  /// No description provided for @fantasyWearBabydoll.
  ///
  /// In tr, this message translates to:
  /// **'Bebek Doll'**
  String get fantasyWearBabydoll;

  /// No description provided for @fantasyWearChemise.
  ///
  /// In tr, this message translates to:
  /// **'Gecelik'**
  String get fantasyWearChemise;

  /// No description provided for @fantasyWearTeddy.
  ///
  /// In tr, this message translates to:
  /// **'Teddy'**
  String get fantasyWearTeddy;

  /// No description provided for @fantasyWearBodysuit.
  ///
  /// In tr, this message translates to:
  /// **'Bodysuit'**
  String get fantasyWearBodysuit;

  /// No description provided for @fantasyWearCorset.
  ///
  /// In tr, this message translates to:
  /// **'Korse'**
  String get fantasyWearCorset;

  /// No description provided for @fantasyWearBustier.
  ///
  /// In tr, this message translates to:
  /// **'Büstiye'**
  String get fantasyWearBustier;

  /// No description provided for @fantasyWearGarter.
  ///
  /// In tr, this message translates to:
  /// **'Jartiyer'**
  String get fantasyWearGarter;

  /// No description provided for @fantasyWearRobe.
  ///
  /// In tr, this message translates to:
  /// **'Sabahlık'**
  String get fantasyWearRobe;

  /// No description provided for @fantasyWearKimono.
  ///
  /// In tr, this message translates to:
  /// **'Kimono'**
  String get fantasyWearKimono;

  /// No description provided for @fantasyWearCostume.
  ///
  /// In tr, this message translates to:
  /// **'Kostüm'**
  String get fantasyWearCostume;

  /// No description provided for @fantasyWearRolePlay.
  ///
  /// In tr, this message translates to:
  /// **'Rol Oyunu'**
  String get fantasyWearRolePlay;

  /// No description provided for @fantasyWearSleepwear.
  ///
  /// In tr, this message translates to:
  /// **'Pijama'**
  String get fantasyWearSleepwear;

  /// No description provided for @fantasyWearOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get fantasyWearOther;

  /// No description provided for @boostScreenTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mülkü Öne Çıkar'**
  String get boostScreenTitle;

  /// No description provided for @addMoreProperties.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla mülk ekle'**
  String get addMoreProperties;

  /// No description provided for @noMorePropertiesToAdd.
  ///
  /// In tr, this message translates to:
  /// **'Eklemek için daha fazla mülkünüz yok.'**
  String get noMorePropertiesToAdd;

  /// No description provided for @selectBoostDuration.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarma süresini seçin (Gün):'**
  String get selectBoostDuration;

  /// No description provided for @propertiesBoostedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'{count} mülk başarıyla öne çıkarıldı!'**
  String propertiesBoostedSuccessfully(Object count);

  /// No description provided for @completePayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeyi Tamamla'**
  String get completePayment;

  /// No description provided for @userNotAuthenticated.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı doğrulanmamış.'**
  String get userNotAuthenticated;

  /// No description provided for @propertyNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Mülk bulunamadı.'**
  String get propertyNotFound;

  /// No description provided for @noPermissionToBoost.
  ///
  /// In tr, this message translates to:
  /// **'Bu mülkü öne çıkarma yetkiniz yok.'**
  String get noPermissionToBoost;

  /// No description provided for @extras.
  ///
  /// In tr, this message translates to:
  /// **'Ekstralar'**
  String get extras;

  /// No description provided for @requestInfo.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi Al'**
  String get requestInfo;

  /// No description provided for @requestingInfo.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi alınıyor'**
  String get requestingInfo;

  /// No description provided for @listingDate.
  ///
  /// In tr, this message translates to:
  /// **'İlan tarihi'**
  String get listingDate;

  /// No description provided for @profileImageUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Profil fotoğrafınız güncellendi.'**
  String get profileImageUpdated;

  /// No description provided for @profileImageUploadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Profil resmi yüklenemedi'**
  String get profileImageUploadFailed;

  /// No description provided for @editProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Düzenle'**
  String get editProfile;

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @subscriptions.
  ///
  /// In tr, this message translates to:
  /// **'Üyelikler'**
  String get subscriptions;

  /// No description provided for @billingInfo.
  ///
  /// In tr, this message translates to:
  /// **'Fatura Bilgileri'**
  String get billingInfo;

  /// No description provided for @info.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi'**
  String get info;

  /// No description provided for @support.
  ///
  /// In tr, this message translates to:
  /// **'Destek'**
  String get support;

  /// No description provided for @logoutTitle.
  ///
  /// In tr, this message translates to:
  /// **'ÇIKIŞ'**
  String get logoutTitle;

  /// No description provided for @logoutConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yapmak istediğinizden emin misiniz?'**
  String get logoutConfirmation;

  /// No description provided for @no.
  ///
  /// In tr, this message translates to:
  /// **'Hayır'**
  String get no;

  /// No description provided for @createAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Oluştur'**
  String get createAccount;

  /// No description provided for @accountType.
  ///
  /// In tr, this message translates to:
  /// **'Hesap Türü'**
  String get accountType;

  /// No description provided for @individual.
  ///
  /// In tr, this message translates to:
  /// **'Bireysel'**
  String get individual;

  /// No description provided for @corporate.
  ///
  /// In tr, this message translates to:
  /// **'Kurumsal'**
  String get corporate;

  /// No description provided for @agency.
  ///
  /// In tr, this message translates to:
  /// **'Acente'**
  String get agency;

  /// No description provided for @name.
  ///
  /// In tr, this message translates to:
  /// **'İsim'**
  String get name;

  /// No description provided for @surname.
  ///
  /// In tr, this message translates to:
  /// **'Soyisim'**
  String get surname;

  /// No description provided for @phone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon'**
  String get phone;

  /// No description provided for @addSocialMedia.
  ///
  /// In tr, this message translates to:
  /// **'Sosyal Medya Ekle'**
  String get addSocialMedia;

  /// No description provided for @register.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt Ol'**
  String get register;

  /// No description provided for @registerWithGoogle.
  ///
  /// In tr, this message translates to:
  /// **'Google ile Kayıt Ol'**
  String get registerWithGoogle;

  /// No description provided for @registrationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt başarısız.'**
  String get registrationFailed;

  /// No description provided for @registrationFailedWithError.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt başarısız: {error}'**
  String registrationFailedWithError(Object error);

  /// No description provided for @invalidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz e-posta.'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In tr, this message translates to:
  /// **'Şifre en az 6 karakter olmalı.'**
  String get passwordTooShort;

  /// No description provided for @socialMediaAddFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sosyal medya bağlantıları eklenemedi'**
  String get socialMediaAddFailed;

  /// No description provided for @socialMediaAddSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Sosyal medya bağlantıları başarıyla eklendi'**
  String get socialMediaAddSuccess;

  /// No description provided for @enterPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi giriniz'**
  String get enterPassword;

  /// No description provided for @enterEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresinizi giriniz'**
  String get enterEmail;

  /// No description provided for @enterPhone.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numaranızı girin'**
  String get enterPhone;

  /// No description provided for @enter.
  ///
  /// In tr, this message translates to:
  /// **'Giriniz'**
  String get enter;

  /// No description provided for @location.
  ///
  /// In tr, this message translates to:
  /// **'Konum'**
  String get location;

  /// No description provided for @corporateName.
  ///
  /// In tr, this message translates to:
  /// **'Kurum ismi'**
  String get corporateName;

  /// No description provided for @propertyRemovedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Mülk favorilerden kaldırıldı'**
  String get propertyRemovedFromFavorites;

  /// No description provided for @viewFloorPlans.
  ///
  /// In tr, this message translates to:
  /// **'Kat Planlarını Görüntüle'**
  String get viewFloorPlans;

  /// No description provided for @viewPdfFile.
  ///
  /// In tr, this message translates to:
  /// **'PDF Dosyasını Görüntüle'**
  String get viewPdfFile;

  /// No description provided for @auctions.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırmalar'**
  String get auctions;

  /// No description provided for @myAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırmalarım'**
  String get myAuctions;

  /// No description provided for @noMyAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Hiç açık artırmanız yok.'**
  String get noMyAuctions;

  /// No description provided for @unableToCalculateTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam hesaplanamıyor'**
  String get unableToCalculateTotal;

  /// No description provided for @serviceUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Hizmet geçici olarak kullanılamıyor. Lütfen tekrar deneyin.'**
  String get serviceUnavailable;

  /// No description provided for @noActiveAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda aktif açık artırma yok.'**
  String get noActiveAuctions;

  /// No description provided for @currentPrice.
  ///
  /// In tr, this message translates to:
  /// **'Güncel Fiyat'**
  String get currentPrice;

  /// No description provided for @startingPrice.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç Fiyatı'**
  String get startingPrice;

  /// No description provided for @remainingTime.
  ///
  /// In tr, this message translates to:
  /// **'Kalan Süre'**
  String get remainingTime;

  /// No description provided for @myCurrentBids.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Tekliflerim'**
  String get myCurrentBids;

  /// No description provided for @myWins.
  ///
  /// In tr, this message translates to:
  /// **'Kazandıklarım'**
  String get myWins;

  /// No description provided for @myPastAuctions.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş Açık Artırmalarım'**
  String get myPastAuctions;

  /// No description provided for @homePage.
  ///
  /// In tr, this message translates to:
  /// **'Anasayfa'**
  String get homePage;

  /// No description provided for @whatsapp.
  ///
  /// In tr, this message translates to:
  /// **'Whatsapp'**
  String get whatsapp;

  /// No description provided for @facebook.
  ///
  /// In tr, this message translates to:
  /// **'Facebook'**
  String get facebook;

  /// No description provided for @instagram.
  ///
  /// In tr, this message translates to:
  /// **'Instagram'**
  String get instagram;

  /// No description provided for @linkedin.
  ///
  /// In tr, this message translates to:
  /// **'LinkedIn'**
  String get linkedin;

  /// No description provided for @propertyNo.
  ///
  /// In tr, this message translates to:
  /// **'No'**
  String get propertyNo;

  /// No description provided for @copiedToClipboard.
  ///
  /// In tr, this message translates to:
  /// **'Kopyalandı'**
  String get copiedToClipboard;

  /// No description provided for @selectProperty.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Seçin'**
  String get selectProperty;

  /// No description provided for @startAuction.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırmayı Başlat'**
  String get startAuction;

  /// No description provided for @fieldCannotBeEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Bu alan boş bırakılamaz.'**
  String get fieldCannotBeEmpty;

  /// No description provided for @enterValidPrice.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir fiyat girin.'**
  String get enterValidPrice;

  /// No description provided for @pleaseMakeSelection.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir seçim yapın.'**
  String get pleaseMakeSelection;

  /// No description provided for @auctionCreated.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırma başarıyla oluşturuldu!'**
  String get auctionCreated;

  /// No description provided for @auctionCreationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırma oluşturulamadı.'**
  String get auctionCreationFailed;

  /// No description provided for @enterValidBid.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir teklif girin.'**
  String get enterValidBid;

  /// No description provided for @bidMustBeHigher.
  ///
  /// In tr, this message translates to:
  /// **'Teklif en az {minBid} {currency} olmalıdır.'**
  String bidMustBeHigher(Object currency, Object minBid);

  /// No description provided for @newAuction.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Açık Artırma'**
  String get newAuction;

  /// No description provided for @endAuction.
  ///
  /// In tr, this message translates to:
  /// **'Açık Artırmayı Sonlandır'**
  String get endAuction;

  /// No description provided for @noDateInfo.
  ///
  /// In tr, this message translates to:
  /// **'Tarih Bilgisi Yok'**
  String get noDateInfo;

  /// No description provided for @bidPlacedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Teklif başarıyla verildi!'**
  String get bidPlacedSuccessfully;

  /// No description provided for @bidFailed.
  ///
  /// In tr, this message translates to:
  /// **'Teklif verilemedi.'**
  String get bidFailed;

  /// No description provided for @auctionEndedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırma başarıyla sona erdi.'**
  String get auctionEndedSuccessfully;

  /// No description provided for @auctionEndFailed.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırma sonlandırılamadı.'**
  String get auctionEndFailed;

  /// No description provided for @salePrice.
  ///
  /// In tr, this message translates to:
  /// **'Satış Fiyatı'**
  String get salePrice;

  /// No description provided for @placeBid.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Ver'**
  String get placeBid;

  /// No description provided for @bidAmount.
  ///
  /// In tr, this message translates to:
  /// **'Teklif Miktarı'**
  String get bidAmount;

  /// No description provided for @sendReceiptByEmail.
  ///
  /// In tr, this message translates to:
  /// **'Faturayı E-posta ile Gönder'**
  String get sendReceiptByEmail;

  /// No description provided for @pleaseEnterEmail.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir e-posta adresi girin'**
  String get pleaseEnterEmail;

  /// No description provided for @receiptSentSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Fatura başarıyla gönderildi!'**
  String get receiptSentSuccessfully;

  /// No description provided for @sendEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Gönder'**
  String get sendEmail;

  /// No description provided for @sendByEmail.
  ///
  /// In tr, this message translates to:
  /// **'E-posta ile gönder'**
  String get sendByEmail;

  /// No description provided for @receiptWillBeSentToEmail.
  ///
  /// In tr, this message translates to:
  /// **'Faturanız aşağıdaki e-posta adresine gönderilecektir.'**
  String get receiptWillBeSentToEmail;

  /// No description provided for @bids.
  ///
  /// In tr, this message translates to:
  /// **'Teklifler'**
  String get bids;

  /// No description provided for @noBidsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz teklif yok.'**
  String get noBidsYet;

  /// No description provided for @winner.
  ///
  /// In tr, this message translates to:
  /// **'Kazanan'**
  String get winner;

  /// No description provided for @weeks.
  ///
  /// In tr, this message translates to:
  /// **'Hafta'**
  String get weeks;

  /// No description provided for @months.
  ///
  /// In tr, this message translates to:
  /// **'Ay'**
  String get months;

  /// No description provided for @month.
  ///
  /// In tr, this message translates to:
  /// **'Ay'**
  String get month;

  /// No description provided for @week.
  ///
  /// In tr, this message translates to:
  /// **'Hafta'**
  String get week;

  /// No description provided for @day.
  ///
  /// In tr, this message translates to:
  /// **'Gün'**
  String get day;

  /// No description provided for @hour.
  ///
  /// In tr, this message translates to:
  /// **'Saat'**
  String get hour;

  /// No description provided for @winnerInfoLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kazanan bilgileri yüklenemedi.'**
  String get winnerInfoLoadFailed;

  /// No description provided for @auctionYouWon.
  ///
  /// In tr, this message translates to:
  /// **'Kazandığınız Açık Artırma'**
  String get auctionYouWon;

  /// No description provided for @youWonTheAuction.
  ///
  /// In tr, this message translates to:
  /// **'Açık artırmayı kazandınız! Açık Artırma ID: {auctionId}'**
  String youWonTheAuction(Object auctionId);

  /// No description provided for @property.
  ///
  /// In tr, this message translates to:
  /// **'Mülk'**
  String get property;

  /// No description provided for @timeExpired.
  ///
  /// In tr, this message translates to:
  /// **'Süre Doldu'**
  String get timeExpired;

  /// No description provided for @error.
  ///
  /// In tr, this message translates to:
  /// **'Hata'**
  String get error;

  /// No description provided for @analysis.
  ///
  /// In tr, this message translates to:
  /// **'Analiz'**
  String get analysis;

  /// No description provided for @graph.
  ///
  /// In tr, this message translates to:
  /// **'Grafik'**
  String get graph;

  /// No description provided for @searchShipments.
  ///
  /// In tr, this message translates to:
  /// **'Sevkiyat ara'**
  String get searchShipments;

  /// No description provided for @orderId.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş ID'**
  String get orderId;

  /// No description provided for @customer.
  ///
  /// In tr, this message translates to:
  /// **'Müşteri'**
  String get customer;

  /// No description provided for @reviewAlreadyExists.
  ///
  /// In tr, this message translates to:
  /// **'Zaten bir değerlendirme mevcut.'**
  String get reviewAlreadyExists;

  /// No description provided for @noPastBoosts.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş boost bulunmamaktadır.'**
  String get noPastBoosts;

  /// No description provided for @pastBoosts.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş Boostlar'**
  String get pastBoosts;

  /// No description provided for @durationFormat.
  ///
  /// In tr, this message translates to:
  /// **'{days} gün {hours} saat {minutes} dakika'**
  String durationFormat(Object days, Object hours, Object minutes);

  /// No description provided for @earnPayWithPlayPoints.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoints ile Kazan & Öde'**
  String get earnPayWithPlayPoints;

  /// No description provided for @forEveryPurchaseGain.
  ///
  /// In tr, this message translates to:
  /// **'Yaptığınız her alışveriş için 10 PlayPoints kazanın'**
  String get forEveryPurchaseGain;

  /// No description provided for @newBidNotification.
  ///
  /// In tr, this message translates to:
  /// **'Mülkünüz \"{propertyName}\" için {bidAmount} {currency} değerinde yeni teklif var.'**
  String newBidNotification(
      Object bidAmount, Object currency, Object propertyName);

  /// No description provided for @auctionWonNotification.
  ///
  /// In tr, this message translates to:
  /// **'\"{propertyName}\" için açık artırmayı kazandınız!'**
  String auctionWonNotification(Object propertyName);

  /// No description provided for @fillAllFields.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen gerekli alanları doldurun.'**
  String get fillAllFields;

  /// No description provided for @unknownDeliveryDescription.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat detayları mevcut değil.'**
  String get unknownDeliveryDescription;

  /// No description provided for @unknownDeliveryText.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat bilgisi şu anda mevcut değil.'**
  String get unknownDeliveryText;

  /// No description provided for @unknownDeliverySectionTapHint.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat detaylarını görmek için dokunun'**
  String get unknownDeliverySectionTapHint;

  /// No description provided for @fastDeliveryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Teslimat'**
  String get fastDeliveryTitle;

  /// No description provided for @selfDeliveryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kendi Teslimatı'**
  String get selfDeliveryTitle;

  /// No description provided for @unknownDeliveryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Seçeneği'**
  String get unknownDeliveryTitle;

  /// No description provided for @selfDeliveryText.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün satıcı tarafından kendi teslimatıyla sağlanacaktır.'**
  String get selfDeliveryText;

  /// No description provided for @fastDeliveryText.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün hızlı teslimat seçeneğine sahiptir.'**
  String get fastDeliveryText;

  /// No description provided for @selfDeliverySectionTapHint.
  ///
  /// In tr, this message translates to:
  /// **'Kendi teslimat detaylarını görmek için dokunun'**
  String get selfDeliverySectionTapHint;

  /// No description provided for @fastDeliverySectionTapHint.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı teslimat detaylarını görmek için dokunun'**
  String get fastDeliverySectionTapHint;

  /// No description provided for @deliveryIconLabel.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat İkonu'**
  String get deliveryIconLabel;

  /// No description provided for @translationFailed.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama çevrilemedi. Lütfen tekrar deneyin.'**
  String get translationFailed;

  /// No description provided for @translating.
  ///
  /// In tr, this message translates to:
  /// **'Çeviri yapılıyor...'**
  String get translating;

  /// No description provided for @languageNotSupported.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen dil çeviri için desteklenmiyor.'**
  String get languageNotSupported;

  /// No description provided for @propertyAdded.
  ///
  /// In tr, this message translates to:
  /// **'Mülk başarıyla eklendi'**
  String get propertyAdded;

  /// No description provided for @errorUpdatingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün güncellenirken hata oluştu'**
  String get errorUpdatingProduct;

  /// No description provided for @categoryBooks.
  ///
  /// In tr, this message translates to:
  /// **'Kitaplar'**
  String get categoryBooks;

  /// No description provided for @addressDetails.
  ///
  /// In tr, this message translates to:
  /// **'Adres Detayları'**
  String get addressDetails;

  /// No description provided for @ibanOwnerName.
  ///
  /// In tr, this message translates to:
  /// **'IBAN Sahibi Adı'**
  String get ibanOwnerName;

  /// No description provided for @ibanOwnerSurname.
  ///
  /// In tr, this message translates to:
  /// **'IBAN Sahibi Soyadı'**
  String get ibanOwnerSurname;

  /// No description provided for @selectRegion.
  ///
  /// In tr, this message translates to:
  /// **'Bölge Seçiniz'**
  String get selectRegion;

  /// No description provided for @addCustomer.
  ///
  /// In tr, this message translates to:
  /// **'Müşteri Ekle'**
  String get addCustomer;

  /// No description provided for @customerEmail.
  ///
  /// In tr, this message translates to:
  /// **'Müşteri E-posta'**
  String get customerEmail;

  /// No description provided for @enterEmailAddress.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresini girin'**
  String get enterEmailAddress;

  /// No description provided for @enterValidEmail.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir e-posta girin'**
  String get enterValidEmail;

  /// No description provided for @notPropertyOwner.
  ///
  /// In tr, this message translates to:
  /// **'Mülk sahibi değilsiniz'**
  String get notPropertyOwner;

  /// No description provided for @alreadyInvited.
  ///
  /// In tr, this message translates to:
  /// **'Bu kullanıcıya zaten davet gönderdiniz'**
  String get alreadyInvited;

  /// No description provided for @addedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'başarıyla eklendi'**
  String get addedSuccessfully;

  /// No description provided for @owner.
  ///
  /// In tr, this message translates to:
  /// **'Sahip'**
  String get owner;

  /// No description provided for @invitedYouToProperty.
  ///
  /// In tr, this message translates to:
  /// **'sizi mülke davet etti'**
  String get invitedYouToProperty;

  /// No description provided for @editProperty.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Düzenle'**
  String get editProperty;

  /// No description provided for @propertyName.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Adı'**
  String get propertyName;

  /// No description provided for @rentPrice.
  ///
  /// In tr, this message translates to:
  /// **'Kira Bedeli'**
  String get rentPrice;

  /// No description provided for @propertyUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Mülk başarıyla güncellendi'**
  String get propertyUpdated;

  /// No description provided for @deleteProperty.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Sil'**
  String get deleteProperty;

  /// No description provided for @areYouSureDeleteProperty.
  ///
  /// In tr, this message translates to:
  /// **'Bu mülkü silmek istediğinize emin misiniz?'**
  String get areYouSureDeleteProperty;

  /// No description provided for @propertyDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Mülk başarıyla silindi'**
  String get propertyDeleted;

  /// No description provided for @noPropertiesAdded.
  ///
  /// In tr, this message translates to:
  /// **'Henüz mülk eklenmedi'**
  String get noPropertiesAdded;

  /// No description provided for @noPropertiesFound.
  ///
  /// In tr, this message translates to:
  /// **'Aramanıza uygun mülk bulunamadı'**
  String get noPropertiesFound;

  /// No description provided for @addFlat.
  ///
  /// In tr, this message translates to:
  /// **'Daire Ekle'**
  String get addFlat;

  /// No description provided for @notPaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödenmedi'**
  String get notPaid;

  /// No description provided for @removeCustomer.
  ///
  /// In tr, this message translates to:
  /// **'Müşteriyi Kaldır'**
  String get removeCustomer;

  /// No description provided for @doYouWantToRemoveCustomer.
  ///
  /// In tr, this message translates to:
  /// **'Müşteriyi kaldırmak istiyor musunuz?'**
  String get doYouWantToRemoveCustomer;

  /// No description provided for @customerRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Müşteri kaldırıldı'**
  String get customerRemoved;

  /// No description provided for @addProperty.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Ekle'**
  String get addProperty;

  /// No description provided for @apartment.
  ///
  /// In tr, this message translates to:
  /// **'Apartman'**
  String get apartment;

  /// No description provided for @house.
  ///
  /// In tr, this message translates to:
  /// **'Ev'**
  String get house;

  /// No description provided for @yourProperties.
  ///
  /// In tr, this message translates to:
  /// **'Mülkleriniz'**
  String get yourProperties;

  /// No description provided for @searchProperty.
  ///
  /// In tr, this message translates to:
  /// **'Mülk Ara'**
  String get searchProperty;

  /// No description provided for @noAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adres Yok'**
  String get noAddress;

  /// No description provided for @flat.
  ///
  /// In tr, this message translates to:
  /// **'Daire'**
  String get flat;

  /// No description provided for @flatNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Daire bulunamadı'**
  String get flatNotFound;

  /// No description provided for @acceptInvitation.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Et'**
  String get acceptInvitation;

  /// No description provided for @rejectInvitation.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get rejectInvitation;

  /// No description provided for @payRent.
  ///
  /// In tr, this message translates to:
  /// **'Kira Öde'**
  String get payRent;

  /// No description provided for @invitationAccepted.
  ///
  /// In tr, this message translates to:
  /// **'Davet kabul edildi.'**
  String get invitationAccepted;

  /// No description provided for @invitationRejected.
  ///
  /// In tr, this message translates to:
  /// **'Davet reddedildi.'**
  String get invitationRejected;

  /// No description provided for @clearCategories.
  ///
  /// In tr, this message translates to:
  /// **'Kategorileri Temizle'**
  String get clearCategories;

  /// No description provided for @enterValidRent.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir kira bedeli girin'**
  String get enterValidRent;

  /// No description provided for @flatName.
  ///
  /// In tr, this message translates to:
  /// **'Daire İsmi'**
  String get flatName;

  /// No description provided for @flatAdded.
  ///
  /// In tr, this message translates to:
  /// **'Daire başarıyla eklendi'**
  String get flatAdded;

  /// No description provided for @flatUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Daire başarıyla güncellendi'**
  String get flatUpdated;

  /// No description provided for @deleteFlat.
  ///
  /// In tr, this message translates to:
  /// **'Daire silindi'**
  String get deleteFlat;

  /// No description provided for @areYouSureDeleteFlat.
  ///
  /// In tr, this message translates to:
  /// **'Bu daireyi silmek istediğinizden emin misiniz?'**
  String get areYouSureDeleteFlat;

  /// No description provided for @flatDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Daire başarıyla silindi'**
  String get flatDeleted;

  /// No description provided for @rentalManagement.
  ///
  /// In tr, this message translates to:
  /// **'Kiralama Yönetimi'**
  String get rentalManagement;

  /// No description provided for @collectRent.
  ///
  /// In tr, this message translates to:
  /// **'Kira Topla'**
  String get collectRent;

  /// No description provided for @invitationStatusUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Davet durumu bilinmiyor'**
  String get invitationStatusUnknown;

  /// No description provided for @noInvitations.
  ///
  /// In tr, this message translates to:
  /// **'Davetiye yok'**
  String get noInvitations;

  /// No description provided for @noFavoriteBaskets.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesi yok'**
  String get noFavoriteBaskets;

  /// No description provided for @selectFavoriteBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesi seçin'**
  String get selectFavoriteBasket;

  /// No description provided for @transferredToBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listeye aktarıldı'**
  String get transferredToBasket;

  /// No description provided for @transferToBasket.
  ///
  /// In tr, this message translates to:
  /// **'Transfer'**
  String get transferToBasket;

  /// No description provided for @resendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Tekrar Gönder'**
  String get resendCode;

  /// No description provided for @verifyCode.
  ///
  /// In tr, this message translates to:
  /// **'Kodu Doğrula'**
  String get verifyCode;

  /// No description provided for @enterVerificationCode.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresinize gönderilen 6 haneli doğrulama kodunu girin'**
  String get enterVerificationCode;

  /// No description provided for @noVerificationCode.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu bulunamadı'**
  String get noVerificationCode;

  /// No description provided for @verificationCodeUsed.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu zaten kullanılmış'**
  String get verificationCodeUsed;

  /// No description provided for @verificationCodeExpired.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodunun süresi dolmuş'**
  String get verificationCodeExpired;

  /// No description provided for @invalidVerificationCode.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz doğrulama kodu'**
  String get invalidVerificationCode;

  /// No description provided for @verificationCodeSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama kodu başarıyla gönderildi'**
  String get verificationCodeSent;

  /// No description provided for @editFlat.
  ///
  /// In tr, this message translates to:
  /// **'Daire düzenle'**
  String get editFlat;

  /// No description provided for @noFlatsAdded.
  ///
  /// In tr, this message translates to:
  /// **'Daire eklenmedi'**
  String get noFlatsAdded;

  /// No description provided for @sendReportByEmail.
  ///
  /// In tr, this message translates to:
  /// **'Raporu E-posta ile Gönder'**
  String get sendReportByEmail;

  /// No description provided for @reportWillBeSentToEmail.
  ///
  /// In tr, this message translates to:
  /// **'Raporunuz aşağıdaki e-posta adresine gönderilecek'**
  String get reportWillBeSentToEmail;

  /// No description provided for @reportId.
  ///
  /// In tr, this message translates to:
  /// **'Rapor No'**
  String get reportId;

  /// No description provided for @reportSentSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Rapor başarıyla gönderildi!'**
  String get reportSentSuccessfully;

  /// No description provided for @processingLargeDatasets.
  ///
  /// In tr, this message translates to:
  /// **'Sunucularımızda büyük veri kümelerini işleme'**
  String get processingLargeDatasets;

  /// No description provided for @thisMayTakeAFewMinutes.
  ///
  /// In tr, this message translates to:
  /// **'Büyük raporlar için bu işlem birkaç dakika sürebilir.'**
  String get thisMayTakeAFewMinutes;

  /// No description provided for @noDescription.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama yok'**
  String get noDescription;

  /// No description provided for @model.
  ///
  /// In tr, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @make.
  ///
  /// In tr, this message translates to:
  /// **'Marka'**
  String get make;

  /// No description provided for @carListings.
  ///
  /// In tr, this message translates to:
  /// **'Araç listeleri'**
  String get carListings;

  /// No description provided for @horsepower.
  ///
  /// In tr, this message translates to:
  /// **'Beygir gücü'**
  String get horsepower;

  /// No description provided for @engineSize.
  ///
  /// In tr, this message translates to:
  /// **'Motor hacmi (cc)'**
  String get engineSize;

  /// No description provided for @mileage.
  ///
  /// In tr, this message translates to:
  /// **'Kilometre'**
  String get mileage;

  /// No description provided for @year.
  ///
  /// In tr, this message translates to:
  /// **'Sene'**
  String get year;

  /// No description provided for @carName.
  ///
  /// In tr, this message translates to:
  /// **'Araç ismi'**
  String get carName;

  /// No description provided for @specifications.
  ///
  /// In tr, this message translates to:
  /// **'Özellikler'**
  String get specifications;

  /// No description provided for @listingNo.
  ///
  /// In tr, this message translates to:
  /// **'Liste No'**
  String get listingNo;

  /// No description provided for @checkOutThisCar.
  ///
  /// In tr, this message translates to:
  /// **'Şu araca bakın'**
  String get checkOutThisCar;

  /// No description provided for @carDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Araç başarıyla silindi'**
  String get carDeletedSuccessfully;

  /// No description provided for @confirmDeleteCar.
  ///
  /// In tr, this message translates to:
  /// **'Araç silmeyi onayla'**
  String get confirmDeleteCar;

  /// No description provided for @myCars.
  ///
  /// In tr, this message translates to:
  /// **'Araçlarım'**
  String get myCars;

  /// No description provided for @noCarsAddedYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz araç eklenmedi'**
  String get noCarsAddedYet;

  /// No description provided for @maxImagesAllowed.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 10 görsel yükleyebilirsiniz.'**
  String get maxImagesAllowed;

  /// No description provided for @onlyXMoreImagesAllowed.
  ///
  /// In tr, this message translates to:
  /// **'En fazla {x} görsel yükleyebilirsiniz.'**
  String onlyXMoreImagesAllowed(Object x);

  /// No description provided for @enableBiometricAuth.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik Kimlik Doğrulamayı Etkinleştir'**
  String get enableBiometricAuth;

  /// No description provided for @biometricsNotAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Parmak izi tarayıcı uygun değil'**
  String get biometricsNotAvailable;

  /// No description provided for @biometricsEnablePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik oturum açmayı etkinleştirmek için giriş yapın.'**
  String get biometricsEnablePrompt;

  /// No description provided for @biometricsDisablePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik oturum açmayı devre dışı bırakmak için giriş yapın.'**
  String get biometricsDisablePrompt;

  /// No description provided for @biometricsEnabled.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kimlik doğrulama etkinleştirildi.'**
  String get biometricsEnabled;

  /// No description provided for @biometricsDisabled.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kimlik doğrulama devre dışı bırakıldı.'**
  String get biometricsDisabled;

  /// No description provided for @biometricsToggleFailed.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kimlik doğrulama değiştirilemedi.'**
  String get biometricsToggleFailed;

  /// No description provided for @pleaseLoginFirst.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen önce giriş yapın'**
  String get pleaseLoginFirst;

  /// No description provided for @carUpdatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Araç başarıyla güncellendi'**
  String get carUpdatedSuccessfully;

  /// No description provided for @noInternetConnection.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok. Lütfen ağınızı kontrol edin ve tekrar deneyin.'**
  String get noInternetConnection;

  /// No description provided for @networkError.
  ///
  /// In tr, this message translates to:
  /// **'Ağ hatası. Lütfen bağlantınızı kontrol edin ve tekrar deneyin.'**
  String get networkError;

  /// No description provided for @permissionDenied.
  ///
  /// In tr, this message translates to:
  /// **'İzin reddedildi. Lütfen tekrar deneyin.'**
  String get permissionDenied;

  /// No description provided for @sessionExpired.
  ///
  /// In tr, this message translates to:
  /// **'Oturum süresi doldu. Lütfen tekrar giriş yapın.'**
  String get sessionExpired;

  /// No description provided for @uploadingProfileImage.
  ///
  /// In tr, this message translates to:
  /// **'Profil resmi yükleniyor...'**
  String get uploadingProfileImage;

  /// No description provided for @uploadingCoverImage.
  ///
  /// In tr, this message translates to:
  /// **'Kapak resmi yükleniyor'**
  String get uploadingCoverImage;

  /// No description provided for @uploadingTaxCertificate.
  ///
  /// In tr, this message translates to:
  /// **'Vergi levhası yükleniyor...'**
  String get uploadingTaxCertificate;

  /// No description provided for @savingApplication.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru kaydediliyor...'**
  String get savingApplication;

  /// No description provided for @pleaseWaitSubmissionInProgress.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bekleyin, başvuru gönderiliyor...'**
  String get pleaseWaitSubmissionInProgress;

  /// No description provided for @isRequired.
  ///
  /// In tr, this message translates to:
  /// **'Gerekli'**
  String get isRequired;

  /// No description provided for @editCar.
  ///
  /// In tr, this message translates to:
  /// **'Aracı düzenle'**
  String get editCar;

  /// No description provided for @updateCar.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get updateCar;

  /// No description provided for @enableBiometricTitle.
  ///
  /// In tr, this message translates to:
  /// **'Biometrik giriş aktif et'**
  String get enableBiometricTitle;

  /// No description provided for @enableBiometricDescription.
  ///
  /// In tr, this message translates to:
  /// **'Daha hızlı ve güvenli giriş için biometrik girişi aktif etmek istiyor musunuz?'**
  String get enableBiometricDescription;

  /// No description provided for @biometricsNotEnabledForAccount.
  ///
  /// In tr, this message translates to:
  /// **'Biometrik giriş aktif değil'**
  String get biometricsNotEnabledForAccount;

  /// No description provided for @carListingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Araç Listeleri'**
  String get carListingsTitle;

  /// No description provided for @viewAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Gör'**
  String get viewAll;

  /// No description provided for @selectAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap seç'**
  String get selectAccount;

  /// No description provided for @carRemovedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Araç favorilerden kaldırıldı'**
  String get carRemovedFromFavorites;

  /// No description provided for @favoritesVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Favori Araçlar'**
  String get favoritesVehicles;

  /// No description provided for @used.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıldı'**
  String get used;

  /// No description provided for @helloInterestedInCar.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba, {carName} isimli araç ile ilgileniyorum.'**
  String helloInterestedInCar(Object carName);

  /// No description provided for @emailVerificationTitle.
  ///
  /// In tr, this message translates to:
  /// **'E-posta Doğrulama'**
  String get emailVerificationTitle;

  /// No description provided for @emailVerificationMessage.
  ///
  /// In tr, this message translates to:
  /// **'E-postanıza bir doğrulama bağlantısı gönderildi. Lütfen gelen kutunuzu kontrol edin ve hesabınızı doğrulamak için bağlantıya tıklayın.'**
  String get emailVerificationMessage;

  /// No description provided for @resendVerificationEmail.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama E-postasını Yeniden Gönder'**
  String get resendVerificationEmail;

  /// No description provided for @verificationEmailSent.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama e-postası yeniden gönderildi.'**
  String get verificationEmailSent;

  /// No description provided for @emailNotVerified.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresiniz doğrulanmadı.'**
  String get emailNotVerified;

  /// No description provided for @iHaveVerifiedContinue.
  ///
  /// In tr, this message translates to:
  /// **'Doğruladım, devam et.'**
  String get iHaveVerifiedContinue;

  /// No description provided for @viewPublicProfile.
  ///
  /// In tr, this message translates to:
  /// **'Genel Profil'**
  String get viewPublicProfile;

  /// No description provided for @verified.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulandı'**
  String get verified;

  /// No description provided for @errorFetchingData.
  ///
  /// In tr, this message translates to:
  /// **'Veri alınırken hata oluştu'**
  String get errorFetchingData;

  /// No description provided for @errorFetchingProperties.
  ///
  /// In tr, this message translates to:
  /// **'hata oluştu'**
  String get errorFetchingProperties;

  /// No description provided for @errorFetchingCars.
  ///
  /// In tr, this message translates to:
  /// **'hata oluştu'**
  String get errorFetchingCars;

  /// No description provided for @hello.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba'**
  String get hello;

  /// No description provided for @user.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı'**
  String get user;

  /// No description provided for @interestedInYourListings.
  ///
  /// In tr, this message translates to:
  /// **'İlanlarınızla ilgileniyorum'**
  String get interestedInYourListings;

  /// No description provided for @inappropriateProfileImage.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz profil resmi'**
  String get inappropriateProfileImage;

  /// No description provided for @inappropriateBio.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz biyografi'**
  String get inappropriateBio;

  /// No description provided for @inappropriateListings.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz listeler'**
  String get inappropriateListings;

  /// No description provided for @reportSubmittedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Rapor başarıyla gönderildi'**
  String get reportSubmittedSuccessfully;

  /// No description provided for @errorSubmittingReport.
  ///
  /// In tr, this message translates to:
  /// **'Rapor gönderilirken hata oluştu'**
  String get errorSubmittingReport;

  /// No description provided for @bioUpdatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Bio başarıyla güncellendi'**
  String get bioUpdatedSuccessfully;

  /// No description provided for @errorUpdatingBio.
  ///
  /// In tr, this message translates to:
  /// **'Bio güncellenirken hata oluştu'**
  String get errorUpdatingBio;

  /// No description provided for @noUserName.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı yok'**
  String get noUserName;

  /// No description provided for @bio.
  ///
  /// In tr, this message translates to:
  /// **'Biyografi'**
  String get bio;

  /// No description provided for @enterYourBio.
  ///
  /// In tr, this message translates to:
  /// **'Bio girin'**
  String get enterYourBio;

  /// No description provided for @noBioAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Bio yok'**
  String get noBioAvailable;

  /// No description provided for @sendMessage.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj gönder'**
  String get sendMessage;

  /// No description provided for @propertiesListed.
  ///
  /// In tr, this message translates to:
  /// **'Listelenen mülkler'**
  String get propertiesListed;

  /// No description provided for @vehiclesListed.
  ///
  /// In tr, this message translates to:
  /// **'Listelenen araçlar'**
  String get vehiclesListed;

  /// No description provided for @noListingsAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut ilan yok'**
  String get noListingsAvailable;

  /// No description provided for @userProfile.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı profili'**
  String get userProfile;

  /// No description provided for @companyIdMissing.
  ///
  /// In tr, this message translates to:
  /// **'Şirket Kimliği Eksik'**
  String get companyIdMissing;

  /// No description provided for @settingsSectionTheme.
  ///
  /// In tr, this message translates to:
  /// **'Tema'**
  String get settingsSectionTheme;

  /// No description provided for @settingsTheme.
  ///
  /// In tr, this message translates to:
  /// **'Tema'**
  String get settingsTheme;

  /// No description provided for @darkMode.
  ///
  /// In tr, this message translates to:
  /// **'Gece Modu'**
  String get darkMode;

  /// No description provided for @market.
  ///
  /// In tr, this message translates to:
  /// **'Market'**
  String get market;

  /// No description provided for @applyFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri Uygula'**
  String get applyFilters;

  /// No description provided for @buyNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Al'**
  String get buyNow;

  /// No description provided for @browseAndBuyProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlere göz atın ve satın alın'**
  String get browseAndBuyProducts;

  /// No description provided for @pleaseSelectRating.
  ///
  /// In tr, this message translates to:
  /// **'Derecelendirme Seçiniz'**
  String get pleaseSelectRating;

  /// No description provided for @addedToCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepete eklendi'**
  String get addedToCart;

  /// No description provided for @buyItNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi satın al'**
  String get buyItNow;

  /// No description provided for @productDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Detayları'**
  String get productDetails;

  /// No description provided for @reviews.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirmeler'**
  String get reviews;

  /// No description provided for @userReviews.
  ///
  /// In tr, this message translates to:
  /// **'Yorumlar'**
  String get userReviews;

  /// No description provided for @setting2FA.
  ///
  /// In tr, this message translates to:
  /// **'2FA kuruluyor...'**
  String get setting2FA;

  /// No description provided for @setting2FADesc.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen hesabınız için iki faktörlü kimlik doğrulamayı yapılandırırken bekleyin.'**
  String get setting2FADesc;

  /// No description provided for @disabling2FA.
  ///
  /// In tr, this message translates to:
  /// **'2FA devre dışı bırakılıyor...'**
  String get disabling2FA;

  /// No description provided for @disabling2FADesc.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen hesabınızdan iki faktörlü kimlik doğrulama kaldırılırken bekleyin.'**
  String get disabling2FADesc;

  /// No description provided for @addToCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepete ekle'**
  String get addToCart;

  /// No description provided for @details.
  ///
  /// In tr, this message translates to:
  /// **'Detaylar'**
  String get details;

  /// No description provided for @yourReview.
  ///
  /// In tr, this message translates to:
  /// **'Yorumların'**
  String get yourReview;

  /// No description provided for @writeYourReview.
  ///
  /// In tr, this message translates to:
  /// **'Yorum yaz'**
  String get writeYourReview;

  /// No description provided for @askToSeller.
  ///
  /// In tr, this message translates to:
  /// **'Satıcıya Sor'**
  String get askToSeller;

  /// No description provided for @allReviews.
  ///
  /// In tr, this message translates to:
  /// **'Tüm yorumlar'**
  String get allReviews;

  /// No description provided for @noReviewsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz inceleme yok.'**
  String get noReviewsYet;

  /// No description provided for @refurbished.
  ///
  /// In tr, this message translates to:
  /// **'Yenilenmiş'**
  String get refurbished;

  /// No description provided for @maximum3Videos.
  ///
  /// In tr, this message translates to:
  /// **'You can upload 3 videos'**
  String get maximum3Videos;

  /// No description provided for @marketplace.
  ///
  /// In tr, this message translates to:
  /// **'Market'**
  String get marketplace;

  /// No description provided for @sort.
  ///
  /// In tr, this message translates to:
  /// **'Sırala'**
  String get sort;

  /// No description provided for @cart.
  ///
  /// In tr, this message translates to:
  /// **'Sepet'**
  String get cart;

  /// No description provided for @unknownBrand.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen marka'**
  String get unknownBrand;

  /// No description provided for @sellerName.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı'**
  String get sellerName;

  /// No description provided for @someoneLeftReview.
  ///
  /// In tr, this message translates to:
  /// **'Biri ürününüze yorum bıraktı.'**
  String get someoneLeftReview;

  /// No description provided for @removedFromCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepetden kaldırıldı'**
  String get removedFromCart;

  /// No description provided for @unknownCondition.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen durum'**
  String get unknownCondition;

  /// No description provided for @brandModel.
  ///
  /// In tr, this message translates to:
  /// **'Marka model'**
  String get brandModel;

  /// No description provided for @returnEligibility.
  ///
  /// In tr, this message translates to:
  /// **'İade uygunluğu'**
  String get returnEligibility;

  /// No description provided for @tag.
  ///
  /// In tr, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @keyword.
  ///
  /// In tr, this message translates to:
  /// **'Anahtar Kelime'**
  String get keyword;

  /// No description provided for @confirmDeleteProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü silmek için onaylayın'**
  String get confirmDeleteProduct;

  /// No description provided for @productRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Ürün kaldırıldı'**
  String get productRemoved;

  /// No description provided for @discountApplied.
  ///
  /// In tr, this message translates to:
  /// **'İndirim uygulandı'**
  String get discountApplied;

  /// No description provided for @confirmation.
  ///
  /// In tr, this message translates to:
  /// **'Onaylama'**
  String get confirmation;

  /// No description provided for @enterDiscountPercentage.
  ///
  /// In tr, this message translates to:
  /// **'İndirim yüzdesini girin'**
  String get enterDiscountPercentage;

  /// No description provided for @pleaseEnterValidDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli indirimi girin'**
  String get pleaseEnterValidDiscount;

  /// No description provided for @apply2.
  ///
  /// In tr, this message translates to:
  /// **'Başvur'**
  String get apply2;

  /// No description provided for @tags.
  ///
  /// In tr, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @maxBasketsReached.
  ///
  /// In tr, this message translates to:
  /// **'En fazla favori listesi limitine ulaştınız'**
  String get maxBasketsReached;

  /// No description provided for @enterBasketName.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesi isim girin'**
  String get enterBasketName;

  /// No description provided for @addToBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori Listesine Ekle'**
  String get addToBasket;

  /// No description provided for @createBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesi oluştur'**
  String get createBasket;

  /// No description provided for @removeFromBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesinden kaldır'**
  String get removeFromBasket;

  /// No description provided for @chooseBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesi Seç'**
  String get chooseBasket;

  /// No description provided for @doYouWantToDeleteBasket.
  ///
  /// In tr, this message translates to:
  /// **'Favori listesini silmek istediğinizden emin misiniz?'**
  String get doYouWantToDeleteBasket;

  /// No description provided for @noBasketAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi bir favori listesi yok'**
  String get noBasketAvailable;

  /// No description provided for @create.
  ///
  /// In tr, this message translates to:
  /// **'Oluştur'**
  String get create;

  /// No description provided for @editProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü düzenle'**
  String get editProduct;

  /// No description provided for @boostProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü Öne Çıkar'**
  String get boostProduct;

  /// No description provided for @primaryItem.
  ///
  /// In tr, this message translates to:
  /// **'Ana Ürün'**
  String get primaryItem;

  /// No description provided for @submissionNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim bulunamadı'**
  String get submissionNotFound;

  /// No description provided for @adPaymentAlreadyCompleted.
  ///
  /// In tr, this message translates to:
  /// **'Bu reklam için ödeme işlemi tamamlanmıştır.'**
  String get adPaymentAlreadyCompleted;

  /// No description provided for @paymentCompleted.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Tamamlandı'**
  String get paymentCompleted;

  /// No description provided for @makeDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirim yap'**
  String get makeDiscount;

  /// No description provided for @relatedProducts.
  ///
  /// In tr, this message translates to:
  /// **'İlgili ürünler'**
  String get relatedProducts;

  /// No description provided for @myProductsScreenBody.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerim'**
  String get myProductsScreenBody;

  /// No description provided for @noItemToBoost.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarılacak ürün yok'**
  String get noItemToBoost;

  /// No description provided for @itemNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bulunamadı'**
  String get itemNotFound;

  /// No description provided for @itemsBoostedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler başarıyla öne çıkarıldı'**
  String get itemsBoostedSuccessfully;

  /// No description provided for @addMoreItems.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla ürün ekle'**
  String get addMoreItems;

  /// No description provided for @noMoreItemsToAdd.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla ürün yok'**
  String get noMoreItemsToAdd;

  /// No description provided for @confirmRemoveDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirimi kaldırmak için onaylayın'**
  String get confirmRemoveDiscount;

  /// No description provided for @discountRemoved.
  ///
  /// In tr, this message translates to:
  /// **'İndirim kaldırıldı'**
  String get discountRemoved;

  /// No description provided for @noDiscountToRemove.
  ///
  /// In tr, this message translates to:
  /// **'Kaldırmak için indirim yok'**
  String get noDiscountToRemove;

  /// No description provided for @productInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bilgisi bulunamadı'**
  String get productInfoNotFound;

  /// No description provided for @maxReviewsReached.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başına 2 yoruma izin var'**
  String get maxReviewsReached;

  /// No description provided for @yourReviews.
  ///
  /// In tr, this message translates to:
  /// **'Yorumlarınız'**
  String get yourReviews;

  /// No description provided for @inappropriateProductImage.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz ürün resmi'**
  String get inappropriateProductImage;

  /// No description provided for @inappropriateProduct.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz ürün'**
  String get inappropriateProduct;

  /// No description provided for @favorite.
  ///
  /// In tr, this message translates to:
  /// **'Favori'**
  String get favorite;

  /// No description provided for @report.
  ///
  /// In tr, this message translates to:
  /// **'Şikayet et'**
  String get report;

  /// No description provided for @deals.
  ///
  /// In tr, this message translates to:
  /// **'Fırsatlar'**
  String get deals;

  /// No description provided for @addTitle.
  ///
  /// In tr, this message translates to:
  /// **'Başlık ekle'**
  String get addTitle;

  /// No description provided for @addText.
  ///
  /// In tr, this message translates to:
  /// **'Yazı ekle'**
  String get addText;

  /// No description provided for @addImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel ekle'**
  String get addImage;

  /// No description provided for @addImageSlider.
  ///
  /// In tr, this message translates to:
  /// **'Görsel kaydırıcı ekle'**
  String get addImageSlider;

  /// No description provided for @enterTitle.
  ///
  /// In tr, this message translates to:
  /// **'Başlık giriniz'**
  String get enterTitle;

  /// No description provided for @enterText.
  ///
  /// In tr, this message translates to:
  /// **'Yazı giriniz'**
  String get enterText;

  /// No description provided for @mustBeLoggedIn.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yapmalısınız'**
  String get mustBeLoggedIn;

  /// No description provided for @editContent.
  ///
  /// In tr, this message translates to:
  /// **'İçeriği düzenle'**
  String get editContent;

  /// No description provided for @selectColor.
  ///
  /// In tr, this message translates to:
  /// **'Renk seçiniz'**
  String get selectColor;

  /// No description provided for @select.
  ///
  /// In tr, this message translates to:
  /// **'Seçiniz'**
  String get select;

  /// No description provided for @selectAlignment.
  ///
  /// In tr, this message translates to:
  /// **'Hizalamayı seçin'**
  String get selectAlignment;

  /// No description provided for @selectBackgroundColor.
  ///
  /// In tr, this message translates to:
  /// **'Arka plan rengini seçin'**
  String get selectBackgroundColor;

  /// No description provided for @shopName.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan ismi'**
  String get shopName;

  /// No description provided for @editShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanı düzenle'**
  String get editShop;

  /// No description provided for @createShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan oluşturun'**
  String get createShop;

  /// No description provided for @changeBackgroundColor.
  ///
  /// In tr, this message translates to:
  /// **'Arka plan rengini değiştirin'**
  String get changeBackgroundColor;

  /// No description provided for @shops.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanlar'**
  String get shops;

  /// No description provided for @createYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanınızı Oluşturun'**
  String get createYourShop;

  /// No description provided for @resetFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri sıfırla'**
  String get resetFilters;

  /// No description provided for @searchShops.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan ara'**
  String get searchShops;

  /// No description provided for @noShopsAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut dükkan yok'**
  String get noShopsAvailable;

  /// No description provided for @shopNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan bulunamadı'**
  String get shopNotFound;

  /// No description provided for @addSingleImage.
  ///
  /// In tr, this message translates to:
  /// **'Tek resim ekleme'**
  String get addSingleImage;

  /// No description provided for @editText.
  ///
  /// In tr, this message translates to:
  /// **'Metni düzenle'**
  String get editText;

  /// No description provided for @noContentAdded.
  ///
  /// In tr, this message translates to:
  /// **'İçerik eklenmedi'**
  String get noContentAdded;

  /// No description provided for @noPrice.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat yok'**
  String get noPrice;

  /// No description provided for @creatingCollection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon oluşturuluyor'**
  String get creatingCollection;

  /// No description provided for @deletingCollection.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon siliniyor'**
  String get deletingCollection;

  /// No description provided for @updatingProducts.
  ///
  /// In tr, this message translates to:
  /// **'Koleksiyon güncelleniyor'**
  String get updatingProducts;

  /// No description provided for @createAndNameYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Aşağıdaki alanları doldurarak hızla mağazanızı oluşturabilir, ürünlerinizi sergileyebilir ve satış yapmaya başlayabilirsiniz.'**
  String get createAndNameYourShop;

  /// No description provided for @customizeYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanınızı ihtiyaçlarınızı karşılayacak şekilde özelleştirin'**
  String get customizeYourShop;

  /// No description provided for @publishYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Müşteri çekmek için dükkanınızı yayınlayın'**
  String get publishYourShop;

  /// No description provided for @nameYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanınıza bir isim verin'**
  String get nameYourShop;

  /// No description provided for @enterShopName.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan adını girin'**
  String get enterShopName;

  /// No description provided for @enterShopNameAndCategory.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir dükkan adı girin ve bir kategori seçin'**
  String get enterShopNameAndCategory;

  /// No description provided for @next.
  ///
  /// In tr, this message translates to:
  /// **'İleri'**
  String get next;

  /// No description provided for @electronics.
  ///
  /// In tr, this message translates to:
  /// **'Elektronik'**
  String get electronics;

  /// No description provided for @kitchen.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak'**
  String get kitchen;

  /// No description provided for @beauty.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik'**
  String get beauty;

  /// No description provided for @fashion.
  ///
  /// In tr, this message translates to:
  /// **'Moda'**
  String get fashion;

  /// No description provided for @sports.
  ///
  /// In tr, this message translates to:
  /// **'Spor'**
  String get sports;

  /// No description provided for @toys.
  ///
  /// In tr, this message translates to:
  /// **'Oyuncaklar'**
  String get toys;

  /// No description provided for @automotive.
  ///
  /// In tr, this message translates to:
  /// **'Otomotiv'**
  String get automotive;

  /// No description provided for @books.
  ///
  /// In tr, this message translates to:
  /// **'Kitaplar'**
  String get books;

  /// No description provided for @publish.
  ///
  /// In tr, this message translates to:
  /// **'Yayınla'**
  String get publish;

  /// No description provided for @uploadCoverImage.
  ///
  /// In tr, this message translates to:
  /// **'Kapak resmi'**
  String get uploadCoverImage;

  /// No description provided for @uploadProfileImage.
  ///
  /// In tr, this message translates to:
  /// **'Profil resmi'**
  String get uploadProfileImage;

  /// No description provided for @taxPlateCertificate.
  ///
  /// In tr, this message translates to:
  /// **'Vergi levha belgesi'**
  String get taxPlateCertificate;

  /// No description provided for @enterShopBio.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan biosu girin'**
  String get enterShopBio;

  /// No description provided for @writeShopBio.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan biosu yazın'**
  String get writeShopBio;

  /// No description provided for @tapToUploadCoverImage.
  ///
  /// In tr, this message translates to:
  /// **'Vergi Levha Belgesi yüklemek için dokunun'**
  String get tapToUploadCoverImage;

  /// No description provided for @shopBioTooLong.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan biosu çok uzun'**
  String get shopBioTooLong;

  /// No description provided for @enterAllFields.
  ///
  /// In tr, this message translates to:
  /// **'Tüm alanları girin'**
  String get enterAllFields;

  /// No description provided for @myCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepetim'**
  String get myCart;

  /// No description provided for @favoriteShops.
  ///
  /// In tr, this message translates to:
  /// **'Favori dükkanlar'**
  String get favoriteShops;

  /// No description provided for @noFavoriteShops.
  ///
  /// In tr, this message translates to:
  /// **'Favori yok'**
  String get noFavoriteShops;

  /// Message displayed when items are successfully boosted
  ///
  /// In tr, this message translates to:
  /// **'{totalItems} ürün başarıyla öne çıkarıldı.'**
  String successfullyBoostedItems(Object totalItems);

  /// No description provided for @separateTagsWithCommas.
  ///
  /// In tr, this message translates to:
  /// **'Etiketleri virgülle ayırın'**
  String get separateTagsWithCommas;

  /// No description provided for @tagsAndKeywordsOptional.
  ///
  /// In tr, this message translates to:
  /// **'Etiketler ve Anahtar Kelimeler (Opsiyonel)'**
  String get tagsAndKeywordsOptional;

  /// No description provided for @quantityOptional.
  ///
  /// In tr, this message translates to:
  /// **'Miktar (Opsiyonel)'**
  String get quantityOptional;

  /// No description provided for @pleaseEnterValidNumber.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli numarayı girin'**
  String get pleaseEnterValidNumber;

  /// No description provided for @pleaseEnterPrice.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen fiyat giriniz'**
  String get pleaseEnterPrice;

  /// No description provided for @brandAndModel.
  ///
  /// In tr, this message translates to:
  /// **'Marka ve Model'**
  String get brandAndModel;

  /// No description provided for @pleaseSelectProductCondition.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ürün durumunu seçiniz'**
  String get pleaseSelectProductCondition;

  /// No description provided for @productCondition.
  ///
  /// In tr, this message translates to:
  /// **'Ürün durumu'**
  String get productCondition;

  /// No description provided for @detailedDescriptionOptional.
  ///
  /// In tr, this message translates to:
  /// **'Detaylı açıklama (Opsiyonel)'**
  String get detailedDescriptionOptional;

  /// No description provided for @selectVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video seç'**
  String get selectVideo;

  /// No description provided for @uploadVideoOptional.
  ///
  /// In tr, this message translates to:
  /// **'Video yükleyin (Opsiyonel)'**
  String get uploadVideoOptional;

  /// No description provided for @selectImages.
  ///
  /// In tr, this message translates to:
  /// **'Görsel seç'**
  String get selectImages;

  /// No description provided for @uploadPhotos.
  ///
  /// In tr, this message translates to:
  /// **'Görsel yükle'**
  String get uploadPhotos;

  /// No description provided for @pleaseSelectACategory.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir kategori seçin'**
  String get pleaseSelectACategory;

  /// No description provided for @pleaseEnterProductTitle.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ürün başlığını girin'**
  String get pleaseEnterProductTitle;

  /// No description provided for @productTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başlığı'**
  String get productTitle;

  /// No description provided for @saveSellerInfoForFutureSales.
  ///
  /// In tr, this message translates to:
  /// **'Gelecekteki satışlar için satıcı bilgilerini kaydedin'**
  String get saveSellerInfoForFutureSales;

  /// No description provided for @pleaseEnterYourBankAccountNumberOrIban.
  ///
  /// In tr, this message translates to:
  /// **'IBAN girin'**
  String get pleaseEnterYourBankAccountNumberOrIban;

  /// No description provided for @securePaymentNotice.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yönteminiz güvende'**
  String get securePaymentNotice;

  /// No description provided for @answer.
  ///
  /// In tr, this message translates to:
  /// **'Cevapla'**
  String get answer;

  /// No description provided for @askedBy.
  ///
  /// In tr, this message translates to:
  /// **'Soran'**
  String get askedBy;

  /// No description provided for @deleteQuestionConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Bu soruyu silmek istediğinizden emin misiniz?'**
  String get deleteQuestionConfirmation;

  /// No description provided for @deleteQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Soruyu Sil'**
  String get deleteQuestion;

  /// No description provided for @sendAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevabı Gönder'**
  String get sendAnswer;

  /// No description provided for @writeAnswerPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'Cevabınızı buraya yazın...'**
  String get writeAnswerPlaceholder;

  /// No description provided for @writeDetailedAnswerHelper.
  ///
  /// In tr, this message translates to:
  /// **'Müşterinize yardımcı olacak detaylı bir cevap yazın.'**
  String get writeDetailedAnswerHelper;

  /// No description provided for @writeAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevap Yazın'**
  String get writeAnswer;

  /// No description provided for @editAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevabı Düzenle'**
  String get editAnswer;

  /// No description provided for @unanswered.
  ///
  /// In tr, this message translates to:
  /// **'Cevaplanmamış'**
  String get unanswered;

  /// No description provided for @bankAccountNumberIban.
  ///
  /// In tr, this message translates to:
  /// **'IBAN'**
  String get bankAccountNumberIban;

  /// No description provided for @pleaseEnterYourEmailAddress.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen e-posta adresinizi girin'**
  String get pleaseEnterYourEmailAddress;

  /// No description provided for @emailAddress.
  ///
  /// In tr, this message translates to:
  /// **'E-posta adresiniz'**
  String get emailAddress;

  /// No description provided for @pleaseEnterYourPhoneNumber.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen telefon numaranızı girin'**
  String get pleaseEnterYourPhoneNumber;

  /// No description provided for @pleaseEnterYourName.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen isminizi girin'**
  String get pleaseEnterYourName;

  /// No description provided for @sellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Bilgileri'**
  String get sellerInfo;

  /// No description provided for @sellerReviews.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı değerlendirmeleri'**
  String get sellerReviews;

  /// No description provided for @unsuccessfulDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Başarısız Teslimat'**
  String get unsuccessfulDelivery;

  /// No description provided for @inappropriateProductInformation.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz ürün bilgileri'**
  String get inappropriateProductInformation;

  /// No description provided for @inappropriateName.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz isim'**
  String get inappropriateName;

  /// No description provided for @inappropriateProducts.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz ürünler'**
  String get inappropriateProducts;

  /// No description provided for @propertyNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Mülk adı gereklidir'**
  String get propertyNameRequired;

  /// No description provided for @priceRequired.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat gereklidir'**
  String get priceRequired;

  /// No description provided for @bedroomsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Yatak odası sayısı gereklidir'**
  String get bedroomsRequired;

  /// No description provided for @bathroomsRequired.
  ///
  /// In tr, this message translates to:
  /// **'Banyo sayısı gereklidir'**
  String get bathroomsRequired;

  /// No description provided for @landSizeRequired.
  ///
  /// In tr, this message translates to:
  /// **'Arazi büyüklüğü gereklidir'**
  String get landSizeRequired;

  /// No description provided for @editLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konumu düzenle'**
  String get editLocation;

  /// No description provided for @addNewImages.
  ///
  /// In tr, this message translates to:
  /// **'Yeni resimler ekleyin'**
  String get addNewImages;

  /// No description provided for @totalPriceLabel.
  ///
  /// In tr, this message translates to:
  /// **'Toplam fiyat'**
  String get totalPriceLabel;

  /// No description provided for @removeFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerden kaldır'**
  String get removeFromFavorites;

  /// No description provided for @addToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilere ekle'**
  String get addToFavorites;

  /// No description provided for @shareProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü paylaş'**
  String get shareProduct;

  /// No description provided for @proceedingToPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeye ilerleniyor'**
  String get proceedingToPayment;

  /// No description provided for @yourCartIsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Sepetinizde ürün yok'**
  String get yourCartIsEmpty;

  /// No description provided for @youHaveNoFavoriteProductsYet.
  ///
  /// In tr, this message translates to:
  /// **'Favori ürün yok'**
  String get youHaveNoFavoriteProductsYet;

  /// No description provided for @myFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerim'**
  String get myFavorites;

  /// No description provided for @unknownAccountType.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen hesap türü'**
  String get unknownAccountType;

  /// No description provided for @errorLoadingProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili yüklerken hata oluştu'**
  String get errorLoadingProfile;

  /// No description provided for @tooManyRequests.
  ///
  /// In tr, this message translates to:
  /// **'Too many requests'**
  String get tooManyRequests;

  /// Kullanıcı e-postayı çok hızlı yeniden göndermeye çalıştığında gösterilen mesaj.
  ///
  /// In tr, this message translates to:
  /// **'E-postayı yeniden göndermeden önce lütfen {seconds} saniye bekleyin.'**
  String pleaseWaitBeforeResendingEmail(Object seconds);

  /// No description provided for @updateProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Güncelle'**
  String get updateProfile;

  /// No description provided for @enterPasswordToSaveChanges.
  ///
  /// In tr, this message translates to:
  /// **'Değişiklikleri kaydetmek için şifrenizi girin:'**
  String get enterPasswordToSaveChanges;

  /// No description provided for @enterYourPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenizi girin'**
  String get enterYourPassword;

  /// No description provided for @profileUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Profil başarıyla güncellendi'**
  String get profileUpdated;

  /// No description provided for @profileUpdateFailed.
  ///
  /// In tr, this message translates to:
  /// **'Profil güncellemesi başarısız oldu'**
  String get profileUpdateFailed;

  /// No description provided for @deleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı Sil'**
  String get deleteAccount;

  /// No description provided for @enterPasswordToDeleteAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınızı silmek için şifrenizi girin:'**
  String get enterPasswordToDeleteAccount;

  /// No description provided for @accountDeletionFailed.
  ///
  /// In tr, this message translates to:
  /// **'Hesap silme başarısız oldu'**
  String get accountDeletionFailed;

  /// No description provided for @nameSurname.
  ///
  /// In tr, this message translates to:
  /// **'İsim Soyisim'**
  String get nameSurname;

  /// No description provided for @newPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre'**
  String get newPassword;

  /// No description provided for @myProducts.
  ///
  /// In tr, this message translates to:
  /// **'Vitrin\'deki Ürünlerim'**
  String get myProducts;

  /// No description provided for @noShipmentsFound.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi bir sevkiyat bulunamadı'**
  String get noShipmentsFound;

  /// No description provided for @listedProducts2.
  ///
  /// In tr, this message translates to:
  /// **'Listelenen'**
  String get listedProducts2;

  /// No description provided for @soldProducts2.
  ///
  /// In tr, this message translates to:
  /// **'Satılan'**
  String get soldProducts2;

  /// No description provided for @boughtProducts2.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alınan'**
  String get boughtProducts2;

  /// No description provided for @noListedProducts.
  ///
  /// In tr, this message translates to:
  /// **'Listelenmiş ürününüz yok'**
  String get noListedProducts;

  /// No description provided for @noSoldProducts.
  ///
  /// In tr, this message translates to:
  /// **'Satılan ürününüz yok'**
  String get noSoldProducts;

  /// No description provided for @noBoughtProducts.
  ///
  /// In tr, this message translates to:
  /// **'Satın aldığınız ürün yok'**
  String get noBoughtProducts;

  /// No description provided for @unknownBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Alıcı'**
  String get unknownBuyer;

  /// No description provided for @unknownShipmentStatus.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmiyor'**
  String get unknownShipmentStatus;

  /// No description provided for @productListedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla listelendi'**
  String get productListedSuccessfully;

  /// No description provided for @errorListingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün listelenirken hata oluştu'**
  String get errorListingProduct;

  /// No description provided for @shipmentStatus.
  ///
  /// In tr, this message translates to:
  /// **'Kargolanma durumu'**
  String get shipmentStatus;

  /// No description provided for @reply.
  ///
  /// In tr, this message translates to:
  /// **'Satıcının cevabı'**
  String get reply;

  /// No description provided for @replyToReview.
  ///
  /// In tr, this message translates to:
  /// **'İncelemeye Cevap Ver'**
  String get replyToReview;

  /// No description provided for @writeYourReply.
  ///
  /// In tr, this message translates to:
  /// **'Cevabınızı yazın...'**
  String get writeYourReply;

  /// No description provided for @replyCannotBeEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Cevap boş olamaz.'**
  String get replyCannotBeEmpty;

  /// No description provided for @replySubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Cevabınız gönderildi.'**
  String get replySubmitted;

  /// No description provided for @purchaseSuccessful.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma başarılı!'**
  String get purchaseSuccessful;

  /// No description provided for @purchaseFailed.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma başarısız. Lütfen tekrar deneyin.'**
  String get purchaseFailed;

  /// No description provided for @submit.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get submit;

  /// No description provided for @noYourReviews.
  ///
  /// In tr, this message translates to:
  /// **'Yorumlar'**
  String get noYourReviews;

  /// No description provided for @cannotBuyOwnProduct.
  ///
  /// In tr, this message translates to:
  /// **'Can\'t buy your own product'**
  String get cannotBuyOwnProduct;

  /// No description provided for @productAlreadySold.
  ///
  /// In tr, this message translates to:
  /// **'Product already sold'**
  String get productAlreadySold;

  /// No description provided for @confirmBuyProduct.
  ///
  /// In tr, this message translates to:
  /// **'Confirm to buy the product'**
  String get confirmBuyProduct;

  /// No description provided for @replyFailed.
  ///
  /// In tr, this message translates to:
  /// **'Reply failed'**
  String get replyFailed;

  /// No description provided for @ownerReply.
  ///
  /// In tr, this message translates to:
  /// **'Satıcının cevabı'**
  String get ownerReply;

  /// No description provided for @writeAReply.
  ///
  /// In tr, this message translates to:
  /// **'Cevap yaz'**
  String get writeAReply;

  /// Notification message when a user's product is sold.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz {productName} satıldı.'**
  String yourProductSold(Object productName);

  /// No description provided for @stars.
  ///
  /// In tr, this message translates to:
  /// **'Yıldızlar'**
  String get stars;

  /// No description provided for @submitReply.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get submitReply;

  /// No description provided for @pleaseEnterReply.
  ///
  /// In tr, this message translates to:
  /// **'Cevap girin'**
  String get pleaseEnterReply;

  /// No description provided for @productYouAreBuying.
  ///
  /// In tr, this message translates to:
  /// **'Satın alacağınız ürün'**
  String get productYouAreBuying;

  /// No description provided for @enterPaymentDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi girin'**
  String get enterPaymentDetails;

  /// No description provided for @savedPaymentMethods.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı ödeme yöntemleri'**
  String get savedPaymentMethods;

  /// No description provided for @enterNewPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Yeni ödeme yöntemi girin'**
  String get enterNewPaymentMethod;

  /// No description provided for @savePaymentDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemini kaydedin'**
  String get savePaymentDetails;

  /// No description provided for @confirmPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeyi Tamamla'**
  String get confirmPayment;

  /// No description provided for @pleaseEnterValidPaymentDetails.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir ödeme yöntemi girin.'**
  String get pleaseEnterValidPaymentDetails;

  /// No description provided for @payment.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme'**
  String get payment;

  /// No description provided for @paymentSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Başarılı'**
  String get paymentSuccess;

  /// No description provided for @paymentSuccessful.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeniz Başarılı'**
  String get paymentSuccessful;

  /// No description provided for @thankYouForYourPurchase.
  ///
  /// In tr, this message translates to:
  /// **'Satın aldığınız için teşekkür ederiz!'**
  String get thankYouForYourPurchase;

  /// No description provided for @goToMarket.
  ///
  /// In tr, this message translates to:
  /// **'Market\'e Git'**
  String get goToMarket;

  /// No description provided for @goToPaymentDetails.
  ///
  /// In tr, this message translates to:
  /// **'Faturaları Görüntüle'**
  String get goToPaymentDetails;

  /// No description provided for @receipts.
  ///
  /// In tr, this message translates to:
  /// **'Fişler'**
  String get receipts;

  /// No description provided for @noReceiptsFound.
  ///
  /// In tr, this message translates to:
  /// **'Fiş bulunamadı.'**
  String get noReceiptsFound;

  /// No description provided for @receiptDetails.
  ///
  /// In tr, this message translates to:
  /// **'Fiş Detayları'**
  String get receiptDetails;

  /// No description provided for @receipt.
  ///
  /// In tr, this message translates to:
  /// **'Fiş'**
  String get receipt;

  /// No description provided for @receiptNumber.
  ///
  /// In tr, this message translates to:
  /// **'Makbuz Numarası'**
  String get receiptNumber;

  /// No description provided for @pricePaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödenen Fiyat'**
  String get pricePaid;

  /// No description provided for @paymentMethodUsed.
  ///
  /// In tr, this message translates to:
  /// **'Kullanılan Ödeme Yöntemi'**
  String get paymentMethodUsed;

  /// No description provided for @download.
  ///
  /// In tr, this message translates to:
  /// **'İndir'**
  String get download;

  /// No description provided for @downloadNotImplemented.
  ///
  /// In tr, this message translates to:
  /// **'İndirme henüz uygulanmadı.'**
  String get downloadNotImplemented;

  /// No description provided for @soldProductDetails.
  ///
  /// In tr, this message translates to:
  /// **'Satılan Ürün Detayları'**
  String get soldProductDetails;

  /// No description provided for @receiptNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Makbuz bulunamadı'**
  String get receiptNotFound;

  /// No description provided for @copyReceiptNumber.
  ///
  /// In tr, this message translates to:
  /// **'Makbuzu Kopyala'**
  String get copyReceiptNumber;

  /// No description provided for @receiptNumberCopied.
  ///
  /// In tr, this message translates to:
  /// **'Makbuz numarası panoya kopyalandı.'**
  String get receiptNumberCopied;

  /// No description provided for @markAsShipped.
  ///
  /// In tr, this message translates to:
  /// **'Kargolandı olarak işaretle'**
  String get markAsShipped;

  /// No description provided for @markAsPending.
  ///
  /// In tr, this message translates to:
  /// **'Beklemede olarak işaretle'**
  String get markAsPending;

  /// No description provided for @errorUpdatingShipmentStatus.
  ///
  /// In tr, this message translates to:
  /// **'Kargo durumu güncellenirken hata oluştu'**
  String get errorUpdatingShipmentStatus;

  /// Ürün kargolandığında gönderilen bildirim mesajı
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz \'{productName}\' kargolandı'**
  String shipmentNotificationMessage(Object productName);

  /// No description provided for @buyerDetails.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı Detayları'**
  String get buyerDetails;

  /// No description provided for @soldProducts.
  ///
  /// In tr, this message translates to:
  /// **'Satılan Ürünler'**
  String get soldProducts;

  /// No description provided for @soldProduct.
  ///
  /// In tr, this message translates to:
  /// **'Satılan Ürün'**
  String get soldProduct;

  /// No description provided for @productDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Açıklaması'**
  String get productDescription;

  /// No description provided for @enterNewAddress.
  ///
  /// In tr, this message translates to:
  /// **'Yeni adres girin'**
  String get enterNewAddress;

  /// No description provided for @addressLine1.
  ///
  /// In tr, this message translates to:
  /// **'Adres Satırı 1'**
  String get addressLine1;

  /// No description provided for @addressLine2.
  ///
  /// In tr, this message translates to:
  /// **'Adres Satırı 2'**
  String get addressLine2;

  /// No description provided for @city.
  ///
  /// In tr, this message translates to:
  /// **'Şehir'**
  String get city;

  /// No description provided for @state.
  ///
  /// In tr, this message translates to:
  /// **'State'**
  String get state;

  /// No description provided for @zipCode.
  ///
  /// In tr, this message translates to:
  /// **'Posta Kodu'**
  String get zipCode;

  /// No description provided for @country.
  ///
  /// In tr, this message translates to:
  /// **'Ülke'**
  String get country;

  /// No description provided for @saveAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adresi kaydedin'**
  String get saveAddress;

  /// No description provided for @addressNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Adres bulunamadı'**
  String get addressNotFound;

  /// No description provided for @addressCopiedToClipboard.
  ///
  /// In tr, this message translates to:
  /// **'Adres panoya kopyalandı.'**
  String get addressCopiedToClipboard;

  /// No description provided for @copyAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adresi Kopyala'**
  String get copyAddress;

  /// No description provided for @shipped.
  ///
  /// In tr, this message translates to:
  /// **'Kargolandı'**
  String get shipped;

  /// No description provided for @productNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bulunamadı.'**
  String get productNotFound;

  /// No description provided for @errorFetchingProductDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler aranırken bir hata oluştu.'**
  String get errorFetchingProductDetails;

  /// No description provided for @waitingForShipment.
  ///
  /// In tr, this message translates to:
  /// **'Kargolanmayı bekliyor'**
  String get waitingForShipment;

  /// No description provided for @notificationTypeNotHandled.
  ///
  /// In tr, this message translates to:
  /// **'Bu tür bildirim işlenemiyor.'**
  String get notificationTypeNotHandled;

  /// No description provided for @productOutOfStock2.
  ///
  /// In tr, this message translates to:
  /// **'Stokda yok'**
  String get productOutOfStock2;

  /// No description provided for @createSellerProfile.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı profili oluşturun'**
  String get createSellerProfile;

  /// No description provided for @sellerProfileNumber.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı profili {number}'**
  String sellerProfileNumber(Object number);

  /// No description provided for @productOutOfStockMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz artık stokta yok.'**
  String get productOutOfStockMessage;

  /// No description provided for @pleaseEnterYourReview.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen satıcıya yorum bırakın'**
  String get pleaseEnterYourReview;

  /// No description provided for @review.
  ///
  /// In tr, this message translates to:
  /// **'Yorum'**
  String get review;

  /// No description provided for @leaveAReview.
  ///
  /// In tr, this message translates to:
  /// **'Yorum bırakın'**
  String get leaveAReview;

  /// No description provided for @iHaveReceivedTheProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü teslim aldım'**
  String get iHaveReceivedTheProduct;

  /// No description provided for @iHaveNotReceivedTheProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü henüz Gel Aldım'**
  String get iHaveNotReceivedTheProduct;

  /// No description provided for @transactionNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Transaction not found'**
  String get transactionNotFound;

  /// No description provided for @productReceived.
  ///
  /// In tr, this message translates to:
  /// **'Ürün teslim alındı'**
  String get productReceived;

  /// No description provided for @errorSubmittingReview.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirme bırakılırken hata oldu'**
  String get errorSubmittingReview;

  /// No description provided for @pleaseEnterYourReply.
  ///
  /// In tr, this message translates to:
  /// **'Yanıtla'**
  String get pleaseEnterYourReply;

  /// No description provided for @pleaseUploadAtLeastOnePhoto.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen en az bir fotoğraf yükleyin'**
  String get pleaseUploadAtLeastOnePhoto;

  /// No description provided for @subcategory.
  ///
  /// In tr, this message translates to:
  /// **'Alt Kategori'**
  String get subcategory;

  /// No description provided for @pleaseSelectASubcategory.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir alt kategori seçin'**
  String get pleaseSelectASubcategory;

  /// No description provided for @productUpdatedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla güncellendi'**
  String get productUpdatedSuccessfully;

  /// No description provided for @existingPhotos.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Fotoğraflar'**
  String get existingPhotos;

  /// No description provided for @uploadNewPhotos.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Fotoğraflar Yükleyin'**
  String get uploadNewPhotos;

  /// No description provided for @uploadNewVideoOptional.
  ///
  /// In tr, this message translates to:
  /// **'Yeni video yükleyin (isteğe bağlı)'**
  String get uploadNewVideoOptional;

  /// No description provided for @existingVideo.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut Video'**
  String get existingVideo;

  /// No description provided for @shopApplications.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Başvuruları'**
  String get shopApplications;

  /// No description provided for @noApplications.
  ///
  /// In tr, this message translates to:
  /// **'No pending applications.'**
  String get noApplications;

  /// No description provided for @applicationDetails.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru Detayları'**
  String get applicationDetails;

  /// No description provided for @approve.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get approve;

  /// No description provided for @disapprove.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get disapprove;

  /// No description provided for @sellerInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgisi bulunamadı.'**
  String get sellerInfoNotFound;

  /// No description provided for @itemInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Ürün bilgisi bulunamadı.'**
  String get itemInfoNotFound;

  /// No description provided for @boostExpired.
  ///
  /// In tr, this message translates to:
  /// **'Boost süresi doldu.'**
  String get boostExpired;

  /// No description provided for @applicationApproved.
  ///
  /// In tr, this message translates to:
  /// **'Application approved successfully.'**
  String get applicationApproved;

  /// No description provided for @applicationDisapproved.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru reddedildi.'**
  String get applicationDisapproved;

  /// No description provided for @shopApprovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Tebrikler! Dükkan başvurunuz onaylandı.'**
  String get shopApprovedTitle;

  /// No description provided for @shopDisapprovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan başvurunuz maalesef reddedildi'**
  String get shopDisapprovedTitle;

  /// No description provided for @shopInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Shop info not found'**
  String get shopInfoNotFound;

  /// No description provided for @homeGarden.
  ///
  /// In tr, this message translates to:
  /// **'Ev & Bahçe'**
  String get homeGarden;

  /// No description provided for @toysGames.
  ///
  /// In tr, this message translates to:
  /// **'Oyuncak'**
  String get toysGames;

  /// No description provided for @health.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık'**
  String get health;

  /// No description provided for @pets.
  ///
  /// In tr, this message translates to:
  /// **'Evcil hayvan'**
  String get pets;

  /// No description provided for @applicationSubmittedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru gönderildi'**
  String get applicationSubmittedSuccessfully;

  /// No description provided for @errorSubmittingApplication.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru gönderilirken hata'**
  String get errorSubmittingApplication;

  /// No description provided for @noCategory.
  ///
  /// In tr, this message translates to:
  /// **'Kategori yok'**
  String get noCategory;

  /// No description provided for @getCategoryName.
  ///
  /// In tr, this message translates to:
  /// **'Kategori'**
  String get getCategoryName;

  /// No description provided for @getSubcategoryName.
  ///
  /// In tr, this message translates to:
  /// **'Alt kategori'**
  String get getSubcategoryName;

  /// No description provided for @categoryKitchen.
  ///
  /// In tr, this message translates to:
  /// **'Mutfak'**
  String get categoryKitchen;

  /// No description provided for @categoryBeauty.
  ///
  /// In tr, this message translates to:
  /// **'Güzellik'**
  String get categoryBeauty;

  /// No description provided for @categoryFashion.
  ///
  /// In tr, this message translates to:
  /// **'Moda'**
  String get categoryFashion;

  /// No description provided for @categorySports.
  ///
  /// In tr, this message translates to:
  /// **'Spor'**
  String get categorySports;

  /// No description provided for @categoryHomeGarden.
  ///
  /// In tr, this message translates to:
  /// **'Ev'**
  String get categoryHomeGarden;

  /// No description provided for @categoryToysGames.
  ///
  /// In tr, this message translates to:
  /// **'Oyuncaklar'**
  String get categoryToysGames;

  /// No description provided for @categoryHealth.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık'**
  String get categoryHealth;

  /// No description provided for @categoryPets.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvanlar'**
  String get categoryPets;

  /// No description provided for @compareProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü karşılaştır'**
  String get compareProduct;

  /// No description provided for @compareProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünleri karşılaştır'**
  String get compareProducts;

  /// No description provided for @noSimilarProducts.
  ///
  /// In tr, this message translates to:
  /// **'Benzer ürün yok'**
  String get noSimilarProducts;

  /// No description provided for @similar.
  ///
  /// In tr, this message translates to:
  /// **'Benzer'**
  String get similar;

  /// No description provided for @earnPlayPoint.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoint Kazan'**
  String get earnPlayPoint;

  /// No description provided for @playPoints.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoints'**
  String get playPoints;

  /// No description provided for @yourEstimatedPlayPoints.
  ///
  /// In tr, this message translates to:
  /// **'Sahip olduğunuz PlayPoints'**
  String get yourEstimatedPlayPoints;

  /// No description provided for @usePlayPointsToGetCoolStuff.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoint kullanarak ürün satın alın'**
  String get usePlayPointsToGetCoolStuff;

  /// No description provided for @productsYouCanBuyWithYourPlayPoints.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoint\'leriniz ile alabileceğiniz ürünler'**
  String get productsYouCanBuyWithYourPlayPoints;

  /// No description provided for @notEnoughPlayPoints.
  ///
  /// In tr, this message translates to:
  /// **'Yeterli PlayPoints yok'**
  String get notEnoughPlayPoints;

  /// No description provided for @payWithPlayPoint.
  ///
  /// In tr, this message translates to:
  /// **'PlayPoint ile ödeyin'**
  String get payWithPlayPoint;

  /// No description provided for @youHave.
  ///
  /// In tr, this message translates to:
  /// **'Sizde'**
  String get youHave;

  /// No description provided for @usePlayPointsForPayment.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme için PlayPoint kullanın'**
  String get usePlayPointsForPayment;

  /// No description provided for @pinAddressOnMap.
  ///
  /// In tr, this message translates to:
  /// **'Adresinizi haritada işaretleyin'**
  String get pinAddressOnMap;

  /// No description provided for @use.
  ///
  /// In tr, this message translates to:
  /// **'Kullan'**
  String get use;

  /// No description provided for @playPointsForPayment.
  ///
  /// In tr, this message translates to:
  /// **'Play Points for Payment'**
  String get playPointsForPayment;

  /// No description provided for @showOnMap.
  ///
  /// In tr, this message translates to:
  /// **'Adresi haritada görüntüle'**
  String get showOnMap;

  /// No description provided for @fieldRequired.
  ///
  /// In tr, this message translates to:
  /// **'Bu alan zorunludur.'**
  String get fieldRequired;

  /// No description provided for @invalidCardNumber.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli kart bilgisi girin.'**
  String get invalidCardNumber;

  /// No description provided for @invalidExpiryDate.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli son kullanım tarihi girin (AA/YY).'**
  String get invalidExpiryDate;

  /// No description provided for @invalidCvv.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli CVV girin.'**
  String get invalidCvv;

  /// No description provided for @pinLocationRequired.
  ///
  /// In tr, this message translates to:
  /// **'Konumunuzu haritada işaretleyin.'**
  String get pinLocationRequired;

  /// No description provided for @yourPinLocation.
  ///
  /// In tr, this message translates to:
  /// **'Konumunuzu haritada işaretlerin'**
  String get yourPinLocation;

  /// No description provided for @pinLocation.
  ///
  /// In tr, this message translates to:
  /// **'Adresinizi haritada işaretleyin'**
  String get pinLocation;

  /// No description provided for @deliveryOptions.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Seçenekleri'**
  String get deliveryOptions;

  /// No description provided for @stats.
  ///
  /// In tr, this message translates to:
  /// **'İstatistik'**
  String get stats;

  /// No description provided for @refundRequest.
  ///
  /// In tr, this message translates to:
  /// **'İade Talebi'**
  String get refundRequest;

  /// No description provided for @refundApproved.
  ///
  /// In tr, this message translates to:
  /// **'İade Onaylandı'**
  String get refundApproved;

  /// No description provided for @refundRejected.
  ///
  /// In tr, this message translates to:
  /// **'İade Reddedildi'**
  String get refundRejected;

  /// No description provided for @refundRequestApprovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'İade Talebi Onaylandı'**
  String get refundRequestApprovedTitle;

  /// No description provided for @refundRequestApprovedMessage.
  ///
  /// In tr, this message translates to:
  /// **'İade işleminin tamamlanması için ürünü belirtilen adrese getiriniz lütfen.'**
  String get refundRequestApprovedMessage;

  /// No description provided for @refundRequestRejectedMessage.
  ///
  /// In tr, this message translates to:
  /// **'İade talebiniz reddedildi.'**
  String get refundRequestRejectedMessage;

  /// No description provided for @refundOfficeAddress.
  ///
  /// In tr, this message translates to:
  /// **'İskele, Kalecik, Four Seasons Life, Ana Cadde Yanı Dükkan No:138'**
  String get refundOfficeAddress;

  /// No description provided for @latestArrivals.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Eklenenler'**
  String get latestArrivals;

  /// No description provided for @selfDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı Teslimatı'**
  String get selfDelivery;

  /// No description provided for @fastDelivery.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Teslimat'**
  String get fastDelivery;

  /// No description provided for @selfDeliveryDescription.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün satıcı tarafından teslim edilecektir. Kurulum gerektiren ürünler için bu seçeneği tercih ediniz'**
  String get selfDeliveryDescription;

  /// No description provided for @fastDeliveryDescription.
  ///
  /// In tr, this message translates to:
  /// **'Teslimatı sizden alır ve alıcıya götürürüz. Alıcıdan 75 TL teslimat ücreti kesilir.'**
  String get fastDeliveryDescription;

  /// No description provided for @pleaseSelectDeliveryOption.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir teslimat seçeneği seçin.'**
  String get pleaseSelectDeliveryOption;

  /// Stok azaldığında kalan ürün sayısını gösterir.
  ///
  /// In tr, this message translates to:
  /// **'Son {quantity} ürün'**
  String lastProducts(Object quantity);

  /// No description provided for @continueButton.
  ///
  /// In tr, this message translates to:
  /// **'Devam Et'**
  String get continueButton;

  /// No description provided for @maximum35Characters.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 35 karakter kullanılabilir.'**
  String get maximum35Characters;

  /// No description provided for @maximum45Characters.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 45 karakter kullanılabilir.'**
  String get maximum45Characters;

  /// No description provided for @maximum100Characters.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 100 karakter kullanılabilir.'**
  String get maximum100Characters;

  /// No description provided for @maximum25MB.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum dosya boyutu 25MB\'dır.'**
  String get maximum25MB;

  /// No description provided for @maximum10Images.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 10 resim yükleyebilirsiniz.'**
  String get maximum10Images;

  /// No description provided for @maximum1Video.
  ///
  /// In tr, this message translates to:
  /// **'Sadece bir video yükleyebilirsiniz.'**
  String get maximum1Video;

  /// No description provided for @previewProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü Önizle'**
  String get previewProduct;

  /// No description provided for @video.
  ///
  /// In tr, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @deliveryOption.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat Seçeneği'**
  String get deliveryOption;

  /// No description provided for @confirmAndList.
  ///
  /// In tr, this message translates to:
  /// **'Onayla ve Listele'**
  String get confirmAndList;

  /// No description provided for @noVideoIncluded.
  ///
  /// In tr, this message translates to:
  /// **'Video dahil edilmedi.'**
  String get noVideoIncluded;

  /// No description provided for @errorPreparingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü hazırlarken hata oluştu'**
  String get errorPreparingProduct;

  /// No description provided for @tagsAndKeywords.
  ///
  /// In tr, this message translates to:
  /// **'Tags and keywords'**
  String get tagsAndKeywords;

  /// No description provided for @pleaseEnterQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen miktar giriniz.'**
  String get pleaseEnterQuantity;

  /// No description provided for @pleaseEnterValidQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli bir miktar giriniz.'**
  String get pleaseEnterValidQuantity;

  /// No description provided for @stockInformation.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Miktar Bilgisi'**
  String get stockInformation;

  /// No description provided for @stockInformationDescription.
  ///
  /// In tr, this message translates to:
  /// **'Ürün miktarı sıfır olunca bu ürünün satışı durdurulacaktır. Eğer stoğunuz yenilenirse, ürün miktarını güncelleyiniz.'**
  String get stockInformationDescription;

  /// No description provided for @priceComparison.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat karşılaştırması'**
  String get priceComparison;

  /// No description provided for @viewAnalytics.
  ///
  /// In tr, this message translates to:
  /// **'Analizleri Görüntüle'**
  String get viewAnalytics;

  /// No description provided for @adAnalytics.
  ///
  /// In tr, this message translates to:
  /// **'Reklam Analitikleri'**
  String get adAnalytics;

  /// No description provided for @totalClicks.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Tıklama'**
  String get totalClicks;

  /// No description provided for @conversions.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşümler'**
  String get conversions;

  /// No description provided for @conversionRate.
  ///
  /// In tr, this message translates to:
  /// **'Dönüşüm Oranı'**
  String get conversionRate;

  /// No description provided for @genderDistribution.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet Dağılımı'**
  String get genderDistribution;

  /// No description provided for @ageGroups.
  ///
  /// In tr, this message translates to:
  /// **'Yaş Grupları'**
  String get ageGroups;

  /// No description provided for @noGenderDataAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet verisi mevcut değil'**
  String get noGenderDataAvailable;

  /// No description provided for @noAgeGroupDataAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Yaş grubu verisi mevcut değil'**
  String get noAgeGroupDataAvailable;

  /// No description provided for @failedToLoadAnalytics.
  ///
  /// In tr, this message translates to:
  /// **'Analitikler yüklenemedi'**
  String get failedToLoadAnalytics;

  /// No description provided for @adApprovedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Onaylandı'**
  String get adApprovedMessage;

  /// No description provided for @weekShort.
  ///
  /// In tr, this message translates to:
  /// **'H'**
  String get weekShort;

  /// No description provided for @dayShort.
  ///
  /// In tr, this message translates to:
  /// **'G'**
  String get dayShort;

  /// No description provided for @hourShort.
  ///
  /// In tr, this message translates to:
  /// **'s'**
  String get hourShort;

  /// No description provided for @minuteShort.
  ///
  /// In tr, this message translates to:
  /// **'d'**
  String get minuteShort;

  /// No description provided for @comparison.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştırma'**
  String get comparison;

  /// No description provided for @suggestion.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen'**
  String get suggestion;

  /// No description provided for @similarity.
  ///
  /// In tr, this message translates to:
  /// **'Benzerlik'**
  String get similarity;

  /// No description provided for @removedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerden kaldırıldı'**
  String get removedFromFavorites;

  /// No description provided for @addedToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilere eklendi'**
  String get addedToFavorites;

  /// No description provided for @sellerNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bulunamadı'**
  String get sellerNotFound;

  /// No description provided for @productInCart.
  ///
  /// In tr, this message translates to:
  /// **'Product in cart'**
  String get productInCart;

  /// No description provided for @productAddedToCart.
  ///
  /// In tr, this message translates to:
  /// **'Ürün sepete eklendi'**
  String get productAddedToCart;

  /// No description provided for @pleaseLoginToContinue.
  ///
  /// In tr, this message translates to:
  /// **'Please login to continue'**
  String get pleaseLoginToContinue;

  /// No description provided for @productRemovedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Product removed from favorites.'**
  String get productRemovedFromFavorites;

  /// No description provided for @productAddedToFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Product added to favorites.'**
  String get productAddedToFavorites;

  /// No description provided for @productAlreadyInCart.
  ///
  /// In tr, this message translates to:
  /// **'Product is already in your cart.'**
  String get productAlreadyInCart;

  /// No description provided for @youHaveEarned.
  ///
  /// In tr, this message translates to:
  /// **'Kazandınız'**
  String get youHaveEarned;

  /// No description provided for @youNowHaveTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam'**
  String get youNowHaveTotal;

  /// No description provided for @errorUpdatingClickCount.
  ///
  /// In tr, this message translates to:
  /// **'Error updating click count'**
  String get errorUpdatingClickCount;

  /// No description provided for @takePhoto.
  ///
  /// In tr, this message translates to:
  /// **'Resim çek'**
  String get takePhoto;

  /// No description provided for @selectFromAlbum.
  ///
  /// In tr, this message translates to:
  /// **'Albümden seç'**
  String get selectFromAlbum;

  /// No description provided for @enterNewQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Yeni miktar girin'**
  String get enterNewQuantity;

  /// No description provided for @doYouWantToDeleteProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü kaldırmak istediğinizden emin misiniz?'**
  String get doYouWantToDeleteProduct;

  /// No description provided for @trending.
  ///
  /// In tr, this message translates to:
  /// **'Trend'**
  String get trending;

  /// No description provided for @fiveStar.
  ///
  /// In tr, this message translates to:
  /// **'5-Yıldız'**
  String get fiveStar;

  /// No description provided for @bestSellers.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Satanlar'**
  String get bestSellers;

  /// No description provided for @listTheProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürünü listele'**
  String get listTheProduct;

  /// No description provided for @searchTheProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün ara'**
  String get searchTheProduct;

  /// No description provided for @stock.
  ///
  /// In tr, this message translates to:
  /// **'Stok'**
  String get stock;

  /// No description provided for @unableToDetermineCategory.
  ///
  /// In tr, this message translates to:
  /// **'Category belirlenmesi hatası'**
  String get unableToDetermineCategory;

  /// No description provided for @errorSubmittingProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün listelenirken hata'**
  String get errorSubmittingProduct;

  /// No description provided for @errorUpdatingFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler güncellenirken hata'**
  String get errorUpdatingFavorites;

  /// No description provided for @recentSearches.
  ///
  /// In tr, this message translates to:
  /// **'En son arananlar'**
  String get recentSearches;

  /// No description provided for @noRecentSearches.
  ///
  /// In tr, this message translates to:
  /// **'Arama yok'**
  String get noRecentSearches;

  /// No description provided for @popularSubcategories.
  ///
  /// In tr, this message translates to:
  /// **'Popüler kategoriler'**
  String get popularSubcategories;

  /// No description provided for @noPopularSubcategories.
  ///
  /// In tr, this message translates to:
  /// **'Popüler kategori yok'**
  String get noPopularSubcategories;

  /// No description provided for @welcomeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Nar24\'e Hoşgeldiniz!'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Ne Ararsan Rahatlıkla!'**
  String get welcomeSubtitle;

  /// No description provided for @noLoggedInForNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimlerinizi görmek için giriş yapın'**
  String get noLoggedInForNotifications;

  /// No description provided for @noLoggedInForCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepetinizi görmek için giriş yapın'**
  String get noLoggedInForCart;

  /// No description provided for @noLoggedInForFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favorilerinizi görmek için giriş yapın'**
  String get noLoggedInForFavorites;

  /// No description provided for @registerButton.
  ///
  /// In tr, this message translates to:
  /// **'Üye ol'**
  String get registerButton;

  /// No description provided for @errorUserDisabled.
  ///
  /// In tr, this message translates to:
  /// **'Error user'**
  String get errorUserDisabled;

  /// No description provided for @searchTimeout.
  ///
  /// In tr, this message translates to:
  /// **'Arama zaman aşımına uğradı. Lütfen tekrar deneyin.'**
  String get searchTimeout;

  /// No description provided for @searchError.
  ///
  /// In tr, this message translates to:
  /// **'Arama başarısız oldu. Lütfen tekrar deneyin.'**
  String get searchError;

  /// No description provided for @invalidPhoneNumber.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz telefon numarası'**
  String get invalidPhoneNumber;

  /// No description provided for @contactBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Alıcıyla İletişime Geç'**
  String get contactBuyer;

  /// No description provided for @cannotContactBuyer.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda alıcıyla iletişime geçilemiyor.'**
  String get cannotContactBuyer;

  /// No description provided for @phoneNumberNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numarası bulunamadı.'**
  String get phoneNumberNotFound;

  /// No description provided for @phoneNumberCopiedToClipboard.
  ///
  /// In tr, this message translates to:
  /// **'Telefon numarası panoya kopyalandı.'**
  String get phoneNumberCopiedToClipboard;

  /// No description provided for @copyPhoneNumber.
  ///
  /// In tr, this message translates to:
  /// **'Telefon Numarasını Kopyala'**
  String get copyPhoneNumber;

  /// No description provided for @deletingProductDesc.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ürün mağazanızdan kaldırılırken bekleyin.'**
  String get deletingProductDesc;

  /// No description provided for @productDeletedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başarıyla silindi!'**
  String get productDeletedSuccessfully;

  /// No description provided for @failedToDeleteProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün silinemedi. Lütfen tekrar deneyin.'**
  String get failedToDeleteProduct;

  /// No description provided for @viewProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get viewProfile;

  /// No description provided for @errorUpdatingCartWithDetails.
  ///
  /// In tr, this message translates to:
  /// **'Sepet güncellenirken hata'**
  String get errorUpdatingCartWithDetails;

  /// No description provided for @errorUpdatingCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepet güncellenirken hata'**
  String get errorUpdatingCart;

  /// No description provided for @productRemovedFromCart.
  ///
  /// In tr, this message translates to:
  /// **'Ürün sepetten kaldırıldı'**
  String get productRemovedFromCart;

  /// No description provided for @removeFromCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepetten kaldır'**
  String get removeFromCart;

  /// No description provided for @errorFetchingProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerde hata'**
  String get errorFetchingProducts;

  /// No description provided for @productsListed.
  ///
  /// In tr, this message translates to:
  /// **'Listelenen ürünler'**
  String get productsListed;

  /// No description provided for @companyDetail.
  ///
  /// In tr, this message translates to:
  /// **'Kuruluş detayı'**
  String get companyDetail;

  /// No description provided for @accept.
  ///
  /// In tr, this message translates to:
  /// **'Kabul et'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get decline;

  /// No description provided for @contact.
  ///
  /// In tr, this message translates to:
  /// **'İletişim'**
  String get contact;

  /// No description provided for @members.
  ///
  /// In tr, this message translates to:
  /// **'Üyeler'**
  String get members;

  /// No description provided for @noMembers.
  ///
  /// In tr, this message translates to:
  /// **'Üye yok'**
  String get noMembers;

  /// No description provided for @projects.
  ///
  /// In tr, this message translates to:
  /// **'Projeler'**
  String get projects;

  /// No description provided for @noProjects.
  ///
  /// In tr, this message translates to:
  /// **'Proje yok'**
  String get noProjects;

  /// No description provided for @inviteMember.
  ///
  /// In tr, this message translates to:
  /// **'Davet et'**
  String get inviteMember;

  /// No description provided for @addProject.
  ///
  /// In tr, this message translates to:
  /// **'Proje ekle'**
  String get addProject;

  /// No description provided for @selectImage.
  ///
  /// In tr, this message translates to:
  /// **'Resim Seç'**
  String get selectImage;

  /// No description provided for @changeImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel değiştir'**
  String get changeImage;

  /// No description provided for @saveProject.
  ///
  /// In tr, this message translates to:
  /// **'Projeyi kaydet'**
  String get saveProject;

  /// No description provided for @listYourCompany.
  ///
  /// In tr, this message translates to:
  /// **'Kuruluşunuzu Listeleyin'**
  String get listYourCompany;

  /// No description provided for @createCompany.
  ///
  /// In tr, this message translates to:
  /// **'Create Company'**
  String get createCompany;

  /// No description provided for @companyApplications.
  ///
  /// In tr, this message translates to:
  /// **'Company Applications'**
  String get companyApplications;

  /// No description provided for @submitApplication.
  ///
  /// In tr, this message translates to:
  /// **'Submit Application'**
  String get submitApplication;

  /// No description provided for @companyName.
  ///
  /// In tr, this message translates to:
  /// **'Company Name'**
  String get companyName;

  /// No description provided for @enterCompanyName.
  ///
  /// In tr, this message translates to:
  /// **'Please enter your company name'**
  String get enterCompanyName;

  /// No description provided for @enterBio.
  ///
  /// In tr, this message translates to:
  /// **'Please enter a brief bio'**
  String get enterBio;

  /// No description provided for @selectCoverImage.
  ///
  /// In tr, this message translates to:
  /// **'Select Cover Image'**
  String get selectCoverImage;

  /// No description provided for @applicationSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Your company application has been submitted!'**
  String get applicationSubmitted;

  /// No description provided for @pleaseWaitWhileWeProcessYourReview.
  ///
  /// In tr, this message translates to:
  /// **'İncelemenizi işleme alırken lütfen bekleyin.'**
  String get pleaseWaitWhileWeProcessYourReview;

  /// No description provided for @replyToQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Soruya Cevap Ver'**
  String get replyToQuestion;

  /// No description provided for @writeYourAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevabınızı yazın...'**
  String get writeYourAnswer;

  /// No description provided for @pleaseEnterAnAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir cevap girin'**
  String get pleaseEnterAnAnswer;

  /// No description provided for @submittingAnswer.
  ///
  /// In tr, this message translates to:
  /// **'Cevap gönderiliyor...'**
  String get submittingAnswer;

  /// No description provided for @answerSubmittedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Cevap başarıyla gönderildi!'**
  String get answerSubmittedSuccessfully;

  /// No description provided for @send.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get send;

  /// No description provided for @submittingApplication.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru Gönderiliyor'**
  String get submittingApplication;

  /// No description provided for @pleaseWaitWhileWeProcessYourApplication.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza başvurunuzu işlerken lütfen bekleyin.'**
  String get pleaseWaitWhileWeProcessYourApplication;

  /// No description provided for @preparingPreview.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme Hazırlanıyor'**
  String get preparingPreview;

  /// No description provided for @pleaseWaitWhileWeLoadYourProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün önizlemeniz hazırlanırken lütfen bekleyin.'**
  String get pleaseWaitWhileWeLoadYourProduct;

  /// No description provided for @applicationRejected.
  ///
  /// In tr, this message translates to:
  /// **'Application rejected.'**
  String get applicationRejected;

  /// No description provided for @reject.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get reject;

  /// No description provided for @companyApprovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Company Approved'**
  String get companyApprovedTitle;

  /// No description provided for @companyApprovedBody.
  ///
  /// In tr, this message translates to:
  /// **'Congratulations! Your company \'{companyName}\' has been approved and listed.'**
  String companyApprovedBody(Object companyName);

  /// No description provided for @companyRejectedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Company Rejected'**
  String get companyRejectedTitle;

  /// No description provided for @companyRejectedBody.
  ///
  /// In tr, this message translates to:
  /// **'We\'re sorry, but your company \'{companyName}\' application has been rejected.'**
  String companyRejectedBody(Object companyName);

  /// No description provided for @noCompanies.
  ///
  /// In tr, this message translates to:
  /// **'No companies listed yet.'**
  String get noCompanies;

  /// No description provided for @follow.
  ///
  /// In tr, this message translates to:
  /// **'Takip Et'**
  String get follow;

  /// No description provided for @following.
  ///
  /// In tr, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @companyFollowed.
  ///
  /// In tr, this message translates to:
  /// **'You are now following this company.'**
  String get companyFollowed;

  /// No description provided for @companyUnfollowed.
  ///
  /// In tr, this message translates to:
  /// **'You have unfollowed this company.'**
  String get companyUnfollowed;

  /// No description provided for @companyBioHint.
  ///
  /// In tr, this message translates to:
  /// **'kuruluş biosu'**
  String get companyBioHint;

  /// No description provided for @enterUserEmail.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı e-posta adresi girin'**
  String get enterUserEmail;

  /// No description provided for @enterUserRole.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı rolü girin'**
  String get enterUserRole;

  /// No description provided for @enterProjectName.
  ///
  /// In tr, this message translates to:
  /// **'Proje ismi girin'**
  String get enterProjectName;

  /// No description provided for @projectName.
  ///
  /// In tr, this message translates to:
  /// **'Proje ismi'**
  String get projectName;

  /// No description provided for @marketTitle.
  ///
  /// In tr, this message translates to:
  /// **'Market'**
  String get marketTitle;

  /// No description provided for @marketSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kuzey Kıbrıs\'ta alım ve satım için bulabileceğiniz herşey'**
  String get marketSubtitle;

  /// No description provided for @propertiesTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mülkler'**
  String get propertiesTitle;

  /// No description provided for @propertiesSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kuzey Kıbrıs\'taki en iyi mülkleri keşfedin'**
  String get propertiesSubtitle;

  /// No description provided for @carsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Araçlar'**
  String get carsTitle;

  /// No description provided for @carsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kuzey Kıbrıs\'taki en iyi araçları bulun'**
  String get carsSubtitle;

  /// No description provided for @createShopTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızı Oluşturun & Tasarlayın'**
  String get createShopTitle;

  /// No description provided for @createShopSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızı özelleştirebilir ve müşterileri karşılayabilirsiniz'**
  String get createShopSubtitle;

  /// No description provided for @listCompanyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şirketinizi Listeleyin'**
  String get listCompanyTitle;

  /// No description provided for @listCompanySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Müşterilere burada olduğunuzu göstermek için şirketinizi listeleyin'**
  String get listCompanySubtitle;

  /// No description provided for @letsGo.
  ///
  /// In tr, this message translates to:
  /// **'Başlayın'**
  String get letsGo;

  /// No description provided for @trackGrowthTitle.
  ///
  /// In tr, this message translates to:
  /// **'Büyümenizi Takip Edin'**
  String get trackGrowthTitle;

  /// No description provided for @trackGrowthSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Satışlarınızı görselleştirilmiş grafikler ve sayısal verilerle takip edin'**
  String get trackGrowthSubtitle;

  /// No description provided for @makeSales.
  ///
  /// In tr, this message translates to:
  /// **'Satış Yap'**
  String get makeSales;

  /// No description provided for @earnWhileShopTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş Yaparken Kazanın'**
  String get earnWhileShopTitle;

  /// No description provided for @earnWhileShopSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Yaptığınız her satın alma için oyun puanları kazanın ve onları havalı şeyler almak için harcayın!'**
  String get earnWhileShopSubtitle;

  /// No description provided for @earn.
  ///
  /// In tr, this message translates to:
  /// **'Kazan'**
  String get earn;

  /// No description provided for @unknownSeller.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Satıcı'**
  String get unknownSeller;

  /// No description provided for @productAlreadyBoosted.
  ///
  /// In tr, this message translates to:
  /// **'Ürün zaten öne çıkarıldı'**
  String get productAlreadyBoosted;

  /// No description provided for @seeAllReviews.
  ///
  /// In tr, this message translates to:
  /// **'Hepsini gör'**
  String get seeAllReviews;

  /// No description provided for @translate.
  ///
  /// In tr, this message translates to:
  /// **'Çevir'**
  String get translate;

  /// No description provided for @seeOriginal.
  ///
  /// In tr, this message translates to:
  /// **'Orijinali gör'**
  String get seeOriginal;

  /// No description provided for @boostAnalysisTitle.
  ///
  /// In tr, this message translates to:
  /// **'Boost Analizi'**
  String get boostAnalysisTitle;

  /// No description provided for @ongoingBoosts.
  ///
  /// In tr, this message translates to:
  /// **'Devam Eden Boost\'lar'**
  String get ongoingBoosts;

  /// No description provided for @noOngoingBoosts.
  ///
  /// In tr, this message translates to:
  /// **'Devam eden boost bulunmamaktadır.'**
  String get noOngoingBoosts;

  /// No description provided for @timeLeft.
  ///
  /// In tr, this message translates to:
  /// **'Kalan Süre'**
  String get timeLeft;

  /// No description provided for @ctr.
  ///
  /// In tr, this message translates to:
  /// **'CTR'**
  String get ctr;

  /// No description provided for @confirmPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi Onayla'**
  String get confirmPassword;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In tr, this message translates to:
  /// **'Bu e-posta zaten kullanımda.'**
  String get emailAlreadyInUse;

  /// No description provided for @weakPassword.
  ///
  /// In tr, this message translates to:
  /// **'Zayıf şifre.'**
  String get weakPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler uyuşmuyor.'**
  String get passwordsDoNotMatch;

  /// No description provided for @selectGender.
  ///
  /// In tr, this message translates to:
  /// **'Cinsiyet Seçin'**
  String get selectGender;

  /// No description provided for @male.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get male;

  /// No description provided for @female.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get female;

  /// No description provided for @selectBirthYear.
  ///
  /// In tr, this message translates to:
  /// **'Doğum Yılı Seçin'**
  String get selectBirthYear;

  /// No description provided for @completeYourProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profilinizi Tamamlayın'**
  String get completeYourProfile;

  /// No description provided for @finishRegistration.
  ///
  /// In tr, this message translates to:
  /// **'Kaydı Tamamla'**
  String get finishRegistration;

  /// No description provided for @enterEmailToConfirmDeletion.
  ///
  /// In tr, this message translates to:
  /// **'Hesabı silmek için email adresinizi giriniz'**
  String get enterEmailToConfirmDeletion;

  /// No description provided for @addresses.
  ///
  /// In tr, this message translates to:
  /// **'Adresler'**
  String get addresses;

  /// No description provided for @loginWithBiometrics.
  ///
  /// In tr, this message translates to:
  /// **'Parmak iziniz ile giriş yapın'**
  String get loginWithBiometrics;

  /// No description provided for @loginWithPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifre ile giriş yapın'**
  String get loginWithPassword;

  /// No description provided for @biometricsLocalizedReason.
  ///
  /// In tr, this message translates to:
  /// **'Biometrik giriş'**
  String get biometricsLocalizedReason;

  /// No description provided for @biometricsFailed.
  ///
  /// In tr, this message translates to:
  /// **'Parmak izi tarama hatalı'**
  String get biometricsFailed;

  /// No description provided for @biometricsError.
  ///
  /// In tr, this message translates to:
  /// **'Parmak izi tarayıcı hatası'**
  String get biometricsError;

  /// No description provided for @sellerInfoEmptyText.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir satıcı profili oluşturmadınız.'**
  String get sellerInfoEmptyText;

  /// No description provided for @sellerInfoEmptyButton.
  ///
  /// In tr, this message translates to:
  /// **'Oluştur'**
  String get sellerInfoEmptyButton;

  /// No description provided for @addressesEmptyText.
  ///
  /// In tr, this message translates to:
  /// **'Hiç adres kaydetmediniz. Sipariş vermek için adres ekleyin.'**
  String get addressesEmptyText;

  /// No description provided for @addressesEmptyButton.
  ///
  /// In tr, this message translates to:
  /// **'Adres ekle'**
  String get addressesEmptyButton;

  /// No description provided for @paymentMethodsEmptyText.
  ///
  /// In tr, this message translates to:
  /// **'Herhangi bir ödeme yöntemi yok. Satın alma yapmak için bir ödeme yöntemi ekleyin.'**
  String get paymentMethodsEmptyText;

  /// No description provided for @paymentMethodsEmptyButton.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get paymentMethodsEmptyButton;

  /// No description provided for @addPaymentMethod.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme yöntemi ekle'**
  String get addPaymentMethod;

  /// No description provided for @addAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adres ekle'**
  String get addAddress;

  /// No description provided for @editSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı profili düzenle'**
  String get editSellerInfo;

  /// No description provided for @editAddress.
  ///
  /// In tr, this message translates to:
  /// **'Adres düzenle'**
  String get editAddress;

  /// No description provided for @title2.
  ///
  /// In tr, this message translates to:
  /// **'Satış İstatistikleri'**
  String get title2;

  /// No description provided for @noData.
  ///
  /// In tr, this message translates to:
  /// **'Veri yok'**
  String get noData;

  /// No description provided for @becomeVipTitle.
  ///
  /// In tr, this message translates to:
  /// **'VIP Üye olarak ürünlerin kapsamlı verilerine erişin ve satışlarınızı artırın.'**
  String get becomeVipTitle;

  /// No description provided for @becomeVipSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'VIP Üyelik ücreti 2000 TRY. Profilinizden istediğiniz zaman iptal edebilirsiniz.'**
  String get becomeVipSubtitle;

  /// No description provided for @becomeVipButton.
  ///
  /// In tr, this message translates to:
  /// **'VIP Ol'**
  String get becomeVipButton;

  /// No description provided for @totalEarnings.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Kazanç'**
  String get totalEarnings;

  /// No description provided for @mostClicked.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Tıklanan Ürün'**
  String get mostClicked;

  /// No description provided for @mostFavorited.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Favorilenen Ürün'**
  String get mostFavorited;

  /// No description provided for @mostAddedToCart.
  ///
  /// In tr, this message translates to:
  /// **'Sepete En Çok Eklenen Ürün'**
  String get mostAddedToCart;

  /// No description provided for @highestRated.
  ///
  /// In tr, this message translates to:
  /// **'En Yüksek Puanlı Ürün'**
  String get highestRated;

  /// No description provided for @noSalesYet.
  ///
  /// In tr, this message translates to:
  /// **'Şu anda hiçbir satış yapmadınız. İlk satışınızı yaptığınızda buraya dönebilirsiniz.'**
  String get noSalesYet;

  /// No description provided for @listAProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Listele'**
  String get listAProduct;

  /// No description provided for @vipDashboardTitle.
  ///
  /// In tr, this message translates to:
  /// **'VIP Paneli'**
  String get vipDashboardTitle;

  /// No description provided for @vipNoAccess.
  ///
  /// In tr, this message translates to:
  /// **'VIP erişiminiz yok.'**
  String get vipNoAccess;

  /// No description provided for @vipMostSold.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Satılan İlk 10 Ürün'**
  String get vipMostSold;

  /// No description provided for @vipCartCount.
  ///
  /// In tr, this message translates to:
  /// **'Sepete En Çok Eklenen İlk 10 Ürün'**
  String get vipCartCount;

  /// No description provided for @vipFavCount.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Favorilenen İlk 10 Ürün'**
  String get vipFavCount;

  /// No description provided for @vipClickCount.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Tıklanan İlk 10 Ürün'**
  String get vipClickCount;

  /// No description provided for @vipMostReviews.
  ///
  /// In tr, this message translates to:
  /// **'En Çok Yorumu Olan İlk 10 Ürün'**
  String get vipMostReviews;

  /// No description provided for @vipHighestRated.
  ///
  /// In tr, this message translates to:
  /// **'En Yüksek Puanlı İlk 10 Ürün'**
  String get vipHighestRated;

  /// No description provided for @newReviewTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Yorum ✅'**
  String get newReviewTitle;

  /// No description provided for @newReviewBody.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz için yeni bir yorum yapıldı.'**
  String get newReviewBody;

  /// No description provided for @sellerReviewTitle.
  ///
  /// In tr, this message translates to:
  /// **'Biri Size Yorum Bıraktı! ✅'**
  String get sellerReviewTitle;

  /// No description provided for @sellerReviewBody.
  ///
  /// In tr, this message translates to:
  /// **'Size bir yorum bırakıldı!'**
  String get sellerReviewBody;

  /// No description provided for @productSoldTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Satıldı! 🎉'**
  String get productSoldTitle;

  /// No description provided for @productSoldBody.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz satıldı!'**
  String get productSoldBody;

  /// No description provided for @shipmentUpdateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Gönderi Durumu Güncellendi!'**
  String get shipmentUpdateTitle;

  /// No description provided for @shipmentUpdateBody.
  ///
  /// In tr, this message translates to:
  /// **'Gönderi durumunuz güncellendi!'**
  String get shipmentUpdateBody;

  /// SellOnTeras widget içinde gradient 'Teras' kelimesinden önce gelen metin.
  ///
  /// In tr, this message translates to:
  /// **'Siz de ürünlerinizi '**
  String get sellOnTeras_pre;

  /// SellOnTeras widget içinde gradient 'Teras' kelimesinden sonra gelen metin.
  ///
  /// In tr, this message translates to:
  /// **'\'de listeleyin ve satın'**
  String get sellOnTeras_post;

  /// No description provided for @maxNormalImages.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 10 resim yükleyebilirsiniz.'**
  String get maxNormalImages;

  /// No description provided for @fileTooLarge.
  ///
  /// In tr, this message translates to:
  /// **'Dosya çok büyük'**
  String get fileTooLarge;

  /// No description provided for @addFloorPlan.
  ///
  /// In tr, this message translates to:
  /// **'Kat planı ekle'**
  String get addFloorPlan;

  /// No description provided for @floorName.
  ///
  /// In tr, this message translates to:
  /// **'Kat ismi'**
  String get floorName;

  /// No description provided for @floorNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Kat ismi lazım'**
  String get floorNameRequired;

  /// No description provided for @selectImagePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir resim seçiniz.'**
  String get selectImagePrompt;

  /// No description provided for @maxFloorPlanImages.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 10 kat planı resmi yükleyebilirsiniz.'**
  String get maxFloorPlanImages;

  /// No description provided for @propertyApplicationSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Emlak başvurusu onay için gönderildi.'**
  String get propertyApplicationSubmitted;

  /// No description provided for @propertyApproved.
  ///
  /// In tr, this message translates to:
  /// **'Emlak başarıyla onaylandı.'**
  String get propertyApproved;

  /// No description provided for @propertyRejected.
  ///
  /// In tr, this message translates to:
  /// **'Emlak reddedildi.'**
  String get propertyRejected;

  /// No description provided for @listPropertyApplications.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Başvurularını Listele'**
  String get listPropertyApplications;

  /// No description provided for @propertyType.
  ///
  /// In tr, this message translates to:
  /// **'Emlak Türü'**
  String get propertyType;

  /// No description provided for @noApplicationsFound.
  ///
  /// In tr, this message translates to:
  /// **'Başvuru yok'**
  String get noApplicationsFound;

  /// No description provided for @carApplicationSubmitted.
  ///
  /// In tr, this message translates to:
  /// **'Araç listeleme başvurusu gönderildi'**
  String get carApplicationSubmitted;

  /// No description provided for @listCarApplications.
  ///
  /// In tr, this message translates to:
  /// **'Araç listeleme başvuruları'**
  String get listCarApplications;

  /// No description provided for @carApproved.
  ///
  /// In tr, this message translates to:
  /// **'Araç onaylandı'**
  String get carApproved;

  /// No description provided for @carRejected.
  ///
  /// In tr, this message translates to:
  /// **'Araç reddedildi'**
  String get carRejected;

  /// No description provided for @productApproved.
  ///
  /// In tr, this message translates to:
  /// **'Ürün onaylandı'**
  String get productApproved;

  /// No description provided for @productRejected.
  ///
  /// In tr, this message translates to:
  /// **'Ürün reddedildi'**
  String get productRejected;

  /// No description provided for @listProductApplications.
  ///
  /// In tr, this message translates to:
  /// **'Ürün listeleme başvuruları'**
  String get listProductApplications;

  /// No description provided for @removeAllDiscounts.
  ///
  /// In tr, this message translates to:
  /// **'Tüm İndirimleri Kaldır'**
  String get removeAllDiscounts;

  /// No description provided for @statusBrandNew.
  ///
  /// In tr, this message translates to:
  /// **'Sıfır'**
  String get statusBrandNew;

  /// No description provided for @statusUsed.
  ///
  /// In tr, this message translates to:
  /// **'İkinci El'**
  String get statusUsed;

  /// No description provided for @carTypeAutomobile.
  ///
  /// In tr, this message translates to:
  /// **'Otomobil'**
  String get carTypeAutomobile;

  /// No description provided for @carTypeSuv.
  ///
  /// In tr, this message translates to:
  /// **'SUV'**
  String get carTypeSuv;

  /// No description provided for @carTypePickUp.
  ///
  /// In tr, this message translates to:
  /// **'Pick Up'**
  String get carTypePickUp;

  /// No description provided for @shopOptions.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Ayarları'**
  String get shopOptions;

  /// No description provided for @selectShop.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Seçin'**
  String get selectShop;

  /// No description provided for @carTypeMotorcycle.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet'**
  String get carTypeMotorcycle;

  /// No description provided for @carTypeAtvUtv.
  ///
  /// In tr, this message translates to:
  /// **'ATV/UTV'**
  String get carTypeAtvUtv;

  /// No description provided for @carTypeCaravan.
  ///
  /// In tr, this message translates to:
  /// **'Karavan'**
  String get carTypeCaravan;

  /// No description provided for @carTypeCommercialVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Ticari Araçlar'**
  String get carTypeCommercialVehicles;

  /// No description provided for @carTypeMinivanPanelvan.
  ///
  /// In tr, this message translates to:
  /// **'Minivan/Panelvan'**
  String get carTypeMinivanPanelvan;

  /// No description provided for @carTypeClassicCars.
  ///
  /// In tr, this message translates to:
  /// **'Klasik Arabalar'**
  String get carTypeClassicCars;

  /// No description provided for @carTypeWorkVehicles.
  ///
  /// In tr, this message translates to:
  /// **'İş Araçları'**
  String get carTypeWorkVehicles;

  /// No description provided for @carTypeMarineVehicles.
  ///
  /// In tr, this message translates to:
  /// **'Deniz Araçları'**
  String get carTypeMarineVehicles;

  /// Label to show the total number of products sold by the seller
  ///
  /// In tr, this message translates to:
  /// **'Satılan ürün: {count}'**
  String productsSold(Object count);

  /// No description provided for @sold.
  ///
  /// In tr, this message translates to:
  /// **'Satıldı'**
  String get sold;

  /// No description provided for @view2.
  ///
  /// In tr, this message translates to:
  /// **'Görüntülenme'**
  String get view2;

  /// No description provided for @favorites2.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler'**
  String get favorites2;

  /// No description provided for @productsYouMightLike.
  ///
  /// In tr, this message translates to:
  /// **'İlginizi Çekebilecek Ürünler'**
  String get productsYouMightLike;

  /// No description provided for @rating.
  ///
  /// In tr, this message translates to:
  /// **'Puan'**
  String get rating;

  /// No description provided for @specialProductsForYou.
  ///
  /// In tr, this message translates to:
  /// **'Size Özel Ürünler'**
  String get specialProductsForYou;

  /// No description provided for @selectColors.
  ///
  /// In tr, this message translates to:
  /// **'Renkleri Seç'**
  String get selectColors;

  /// No description provided for @uploadImagesForColors.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen Renkler için Görseller Yükle'**
  String get uploadImagesForColors;

  /// No description provided for @colorsSelected.
  ///
  /// In tr, this message translates to:
  /// **'Renk Seçildi'**
  String get colorsSelected;

  /// No description provided for @colorBlue.
  ///
  /// In tr, this message translates to:
  /// **'Mavi'**
  String get colorBlue;

  /// No description provided for @colorOrange.
  ///
  /// In tr, this message translates to:
  /// **'Turuncu'**
  String get colorOrange;

  /// No description provided for @colorYellow.
  ///
  /// In tr, this message translates to:
  /// **'Sarı'**
  String get colorYellow;

  /// No description provided for @colorBlack.
  ///
  /// In tr, this message translates to:
  /// **'Siyah'**
  String get colorBlack;

  /// No description provided for @colorBrown.
  ///
  /// In tr, this message translates to:
  /// **'Kahverengi'**
  String get colorBrown;

  /// No description provided for @colorDarkBlue.
  ///
  /// In tr, this message translates to:
  /// **'Koyu Mavi'**
  String get colorDarkBlue;

  /// No description provided for @colorGray.
  ///
  /// In tr, this message translates to:
  /// **'Gri'**
  String get colorGray;

  /// No description provided for @colorPink.
  ///
  /// In tr, this message translates to:
  /// **'Pembe'**
  String get colorPink;

  /// No description provided for @colorRed.
  ///
  /// In tr, this message translates to:
  /// **'Kırmızı'**
  String get colorRed;

  /// No description provided for @colorWhite.
  ///
  /// In tr, this message translates to:
  /// **'Beyaz'**
  String get colorWhite;

  /// No description provided for @colorGreen.
  ///
  /// In tr, this message translates to:
  /// **'Yeşil'**
  String get colorGreen;

  /// No description provided for @colorPurple.
  ///
  /// In tr, this message translates to:
  /// **'Mor'**
  String get colorPurple;

  /// No description provided for @colorTeal.
  ///
  /// In tr, this message translates to:
  /// **'Turkuaz'**
  String get colorTeal;

  /// No description provided for @colorLime.
  ///
  /// In tr, this message translates to:
  /// **'Limon Yeşili'**
  String get colorLime;

  /// No description provided for @colorCyan.
  ///
  /// In tr, this message translates to:
  /// **'Camgöbeği'**
  String get colorCyan;

  /// No description provided for @colorMagenta.
  ///
  /// In tr, this message translates to:
  /// **'Macenta'**
  String get colorMagenta;

  /// No description provided for @colorIndigo.
  ///
  /// In tr, this message translates to:
  /// **'Çivit Mavisi'**
  String get colorIndigo;

  /// No description provided for @colorAmber.
  ///
  /// In tr, this message translates to:
  /// **'Kehribar'**
  String get colorAmber;

  /// No description provided for @colorDeepOrange.
  ///
  /// In tr, this message translates to:
  /// **'Koyu Turuncu'**
  String get colorDeepOrange;

  /// No description provided for @colorLightBlue.
  ///
  /// In tr, this message translates to:
  /// **'Açık Mavi'**
  String get colorLightBlue;

  /// No description provided for @colorDeepPurple.
  ///
  /// In tr, this message translates to:
  /// **'Koyu Mor'**
  String get colorDeepPurple;

  /// No description provided for @colorLightGreen.
  ///
  /// In tr, this message translates to:
  /// **'Açık Yeşil'**
  String get colorLightGreen;

  /// No description provided for @colorDarkGray.
  ///
  /// In tr, this message translates to:
  /// **'Koyu Gri'**
  String get colorDarkGray;

  /// No description provided for @colorBeige.
  ///
  /// In tr, this message translates to:
  /// **'Bej'**
  String get colorBeige;

  /// No description provided for @colorTurquoise.
  ///
  /// In tr, this message translates to:
  /// **'Turkuaz'**
  String get colorTurquoise;

  /// No description provided for @colorViolet.
  ///
  /// In tr, this message translates to:
  /// **'Menekşe'**
  String get colorViolet;

  /// No description provided for @colorOlive.
  ///
  /// In tr, this message translates to:
  /// **'Zeytin Yeşili'**
  String get colorOlive;

  /// No description provided for @colorMaroon.
  ///
  /// In tr, this message translates to:
  /// **'Bordo'**
  String get colorMaroon;

  /// No description provided for @colorNavy.
  ///
  /// In tr, this message translates to:
  /// **'Lacivert'**
  String get colorNavy;

  /// No description provided for @colorSilver.
  ///
  /// In tr, this message translates to:
  /// **'Gümüş'**
  String get colorSilver;

  /// No description provided for @errorLoadingReviews.
  ///
  /// In tr, this message translates to:
  /// **'Değerlendirmeler yüklenirken hata gerçekleşti'**
  String get errorLoadingReviews;

  /// No description provided for @pleaseSelectCategoryFirst.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ilk önce kategori seçin'**
  String get pleaseSelectCategoryFirst;

  /// No description provided for @imageSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilmiş görseller'**
  String get imageSelected;

  /// No description provided for @max3Images.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 3 görsel'**
  String get max3Images;

  /// No description provided for @enterPrice.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat girin'**
  String get enterPrice;

  /// No description provided for @enterProductTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün başlığı girin'**
  String get enterProductTitle;

  /// No description provided for @enterDetailedDescription.
  ///
  /// In tr, this message translates to:
  /// **'Açıklama girin'**
  String get enterDetailedDescription;

  /// No description provided for @addVideoandImages.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf & Video'**
  String get addVideoandImages;

  /// No description provided for @goToMyProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlerim'**
  String get goToMyProducts;

  /// No description provided for @searchResults.
  ///
  /// In tr, this message translates to:
  /// **'Arama sonuçları'**
  String get searchResults;

  /// No description provided for @noVehiclesFound.
  ///
  /// In tr, this message translates to:
  /// **'Araç bulunamadı'**
  String get noVehiclesFound;

  /// No description provided for @deleteShopConfirmation.
  ///
  /// In tr, this message translates to:
  /// **'Dükkanı silmek mi istiyorsunuz?'**
  String get deleteShopConfirmation;

  /// No description provided for @pickVideo.
  ///
  /// In tr, this message translates to:
  /// **'Video yükle'**
  String get pickVideo;

  /// No description provided for @selectColorOption.
  ///
  /// In tr, this message translates to:
  /// **'Renk Seçeneği Seçin'**
  String get selectColorOption;

  /// No description provided for @addColorOptions.
  ///
  /// In tr, this message translates to:
  /// **'Renk seçenekleri ekle'**
  String get addColorOptions;

  /// No description provided for @shopAlreadyBoosted.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan zaten boostlu'**
  String get shopAlreadyBoosted;

  /// No description provided for @addMoreColorOptions.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla renk seçeneği ekle'**
  String get addMoreColorOptions;

  /// No description provided for @selectImageForColor.
  ///
  /// In tr, this message translates to:
  /// **'Renk için resim seç'**
  String get selectImageForColor;

  /// No description provided for @maximum10ImagesPerColor.
  ///
  /// In tr, this message translates to:
  /// **'Her renk için en fazla 10 resim yükleyebilirsiniz.'**
  String get maximum10ImagesPerColor;

  /// Maksimum renk seçeneklerine ulaşıldığında gösterilen mesaj
  ///
  /// In tr, this message translates to:
  /// **'{maxColors} renk seçeneğine kadar ekleyebilirsiniz.'**
  String maximumColorOptionsReached(Object maxColors);

  /// No description provided for @uploadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yükleme başarısız'**
  String get uploadFailed;

  /// No description provided for @failedToGenerateComments.
  ///
  /// In tr, this message translates to:
  /// **'Yorum üretirken hata'**
  String get failedToGenerateComments;

  /// No description provided for @totalProductsSold.
  ///
  /// In tr, this message translates to:
  /// **'Toplam satılan ürünler'**
  String get totalProductsSold;

  /// No description provided for @clickCount.
  ///
  /// In tr, this message translates to:
  /// **'Tıklama'**
  String get clickCount;

  /// No description provided for @favoritesCount.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler'**
  String get favoritesCount;

  /// No description provided for @purchaseCount.
  ///
  /// In tr, this message translates to:
  /// **'Satın alınma'**
  String get purchaseCount;

  /// No description provided for @highlyRecommended.
  ///
  /// In tr, this message translates to:
  /// **'Yüksek tavsiye edilen'**
  String get highlyRecommended;

  /// No description provided for @considerOtherOptions.
  ///
  /// In tr, this message translates to:
  /// **'Başka seçenekleri değerlendirin'**
  String get considerOtherOptions;

  /// No description provided for @generatingComments.
  ///
  /// In tr, this message translates to:
  /// **'Yorum üretiyor'**
  String get generatingComments;

  /// No description provided for @chatInfoNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Sohbet bilgisi bulunamadı'**
  String get chatInfoNotFound;

  /// No description provided for @productSold.
  ///
  /// In tr, this message translates to:
  /// **'ürün satıldı'**
  String get productSold;

  /// No description provided for @invitation.
  ///
  /// In tr, this message translates to:
  /// **'Davet'**
  String get invitation;

  /// No description provided for @rentInvitation.
  ///
  /// In tr, this message translates to:
  /// **'Kira Daveti'**
  String get rentInvitation;

  /// No description provided for @shipment.
  ///
  /// In tr, this message translates to:
  /// **'Gönderim'**
  String get shipment;

  /// No description provided for @shopApproved.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Onaylandı'**
  String get shopApproved;

  /// No description provided for @shopDisapproved.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Onaylanmadı'**
  String get shopDisapproved;

  /// No description provided for @message.
  ///
  /// In tr, this message translates to:
  /// **'Mesaj'**
  String get message;

  /// No description provided for @notification.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim'**
  String get notification;

  /// No description provided for @boostStartTime.
  ///
  /// In tr, this message translates to:
  /// **'Boost başlangıç'**
  String get boostStartTime;

  /// No description provided for @boostEndTime.
  ///
  /// In tr, this message translates to:
  /// **'Boost bitiş'**
  String get boostEndTime;

  /// No description provided for @boostDuration.
  ///
  /// In tr, this message translates to:
  /// **'Boost süresi'**
  String get boostDuration;

  /// No description provided for @pricePerDayPerItem.
  ///
  /// In tr, this message translates to:
  /// **'Günlük ücret'**
  String get pricePerDayPerItem;

  /// No description provided for @totalBoostPrice.
  ///
  /// In tr, this message translates to:
  /// **'Toplam ücret'**
  String get totalBoostPrice;

  /// No description provided for @maxFloorPlans.
  ///
  /// In tr, this message translates to:
  /// **'En fazla kat planı'**
  String get maxFloorPlans;

  /// No description provided for @selectFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosya seçin'**
  String get selectFile;

  /// No description provided for @invalidFileType.
  ///
  /// In tr, this message translates to:
  /// **'Uygunsuz dosya türü'**
  String get invalidFileType;

  /// No description provided for @selectFilePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Dosya seçin'**
  String get selectFilePrompt;

  /// No description provided for @floorPlans.
  ///
  /// In tr, this message translates to:
  /// **'Kat planları'**
  String get floorPlans;

  /// No description provided for @properties.
  ///
  /// In tr, this message translates to:
  /// **'Mülkler'**
  String get properties;

  /// No description provided for @vehicles.
  ///
  /// In tr, this message translates to:
  /// **'Araçlar'**
  String get vehicles;

  /// No description provided for @noOngoingBoostsForAnalysis.
  ///
  /// In tr, this message translates to:
  /// **'No ongoing boosts'**
  String get noOngoingBoostsForAnalysis;

  /// No description provided for @searchProperties.
  ///
  /// In tr, this message translates to:
  /// **'Mülk ara'**
  String get searchProperties;

  /// No description provided for @searchCars.
  ///
  /// In tr, this message translates to:
  /// **'Araç ara'**
  String get searchCars;

  /// No description provided for @listedProductsEmptyText.
  ///
  /// In tr, this message translates to:
  /// **'Ürün listeleyin ve geniş bir kitleye satış yapmaya başlayın.'**
  String get listedProductsEmptyText;

  /// No description provided for @noSoldProductsText.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir ürün satmadınız. Bir ürün listeleyin ve ilk satışınızı yapın.'**
  String get noSoldProductsText;

  /// No description provided for @noBoughtProductsText.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bir ürün satın satın almadınız. Alışverişin tadını çıkarın!'**
  String get noBoughtProductsText;

  /// No description provided for @listProductButton.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Listele'**
  String get listProductButton;

  /// No description provided for @goToMarketButton.
  ///
  /// In tr, this message translates to:
  /// **'Market\'e git'**
  String get goToMarketButton;

  /// No description provided for @noActiveBoostMessage.
  ///
  /// In tr, this message translates to:
  /// **'Aktif bir boost\'unuz yok. Bir ürünü boost\'layın ve satışlarınızı artırmak için hedef kitlenize ulaşın.'**
  String get noActiveBoostMessage;

  /// No description provided for @boostProductButton.
  ///
  /// In tr, this message translates to:
  /// **'Bir Ürünü Boost\'la'**
  String get boostProductButton;

  /// No description provided for @addLinkOptional.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı Ekle (İsteğe Bağlı)'**
  String get addLinkOptional;

  /// No description provided for @chooseAdDestination.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcılar bu reklamı tıkladığında nereye gideceğini seçin'**
  String get chooseAdDestination;

  /// No description provided for @noLink.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı Yok'**
  String get noLink;

  /// No description provided for @noLinkDescription.
  ///
  /// In tr, this message translates to:
  /// **'Reklam hiçbir yere yönlendirmeyecek'**
  String get noLinkDescription;

  /// No description provided for @linkToShop.
  ///
  /// In tr, this message translates to:
  /// **'Mağazaya Bağlantı'**
  String get linkToShop;

  /// No description provided for @navigateToShop.
  ///
  /// In tr, this message translates to:
  /// **'{shopName} mağazasına yönlendir'**
  String navigateToShop(String shopName);

  /// No description provided for @linkToProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürüne Bağlantı'**
  String get linkToProduct;

  /// No description provided for @chooseSpecificProduct.
  ///
  /// In tr, this message translates to:
  /// **'Belirli bir ürün seçin'**
  String get chooseSpecificProduct;

  /// No description provided for @selectOrderForRefund.
  ///
  /// In tr, this message translates to:
  /// **'İade için Sipariş Seç'**
  String get selectOrderForRefund;

  /// No description provided for @selectOrderRefundInfo.
  ///
  /// In tr, this message translates to:
  /// **'İade talep etmek istediğiniz siparişi seçin'**
  String get selectOrderRefundInfo;

  /// No description provided for @noOrdersForRefund.
  ///
  /// In tr, this message translates to:
  /// **'Uygun Sipariş Yok'**
  String get noOrdersForRefund;

  /// No description provided for @noOrdersForRefundDesc.
  ///
  /// In tr, this message translates to:
  /// **'İade talep edebileceğiniz siparişiniz bulunmuyor'**
  String get noOrdersForRefundDesc;

  /// No description provided for @confirmOrderSelection.
  ///
  /// In tr, this message translates to:
  /// **'Seçimi Onayla'**
  String get confirmOrderSelection;

  /// No description provided for @refundFormSelectOrder.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş Seç'**
  String get refundFormSelectOrder;

  /// No description provided for @homeImages.
  ///
  /// In tr, this message translates to:
  /// **'Anasayfa Görselleri'**
  String get homeImages;

  /// No description provided for @coverImages.
  ///
  /// In tr, this message translates to:
  /// **'Kapak Görselleri'**
  String get coverImages;

  /// No description provided for @pleaseSelectCoverImage.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir kapak görseli seçin'**
  String get pleaseSelectCoverImage;

  /// No description provided for @noProductsToLink.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanacak ürün bulunamadı.'**
  String get noProductsToLink;

  /// No description provided for @selectProductToLink.
  ///
  /// In tr, this message translates to:
  /// **'Bağlamak için bir ürün seçin.'**
  String get selectProductToLink;

  /// No description provided for @linkedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Başarıyla bağlandı.'**
  String get linkedSuccessfully;

  /// No description provided for @unlinkedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı başarıyla kaldırıldı.'**
  String get unlinkedSuccessfully;

  /// No description provided for @removedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Başarıyla kaldırıldı.'**
  String get removedSuccessfully;

  /// No description provided for @linked.
  ///
  /// In tr, this message translates to:
  /// **'Bağlandı'**
  String get linked;

  /// No description provided for @doYouWantToLinkToProduct.
  ///
  /// In tr, this message translates to:
  /// **'Bir ürüne bağlamak ister misiniz?'**
  String get doYouWantToLinkToProduct;

  /// No description provided for @profileImage.
  ///
  /// In tr, this message translates to:
  /// **'Profil Görseli'**
  String get profileImage;

  /// No description provided for @home2.
  ///
  /// In tr, this message translates to:
  /// **'Ana Sayfa'**
  String get home2;

  /// No description provided for @shopSettings.
  ///
  /// In tr, this message translates to:
  /// **'Dükkan Görselleri'**
  String get shopSettings;

  /// No description provided for @invalidImageFormat.
  ///
  /// In tr, this message translates to:
  /// **'Sadece JPG, PNG, HEIC, HEIF veya WEBP yükleyebilirsiniz.'**
  String get invalidImageFormat;

  /// No description provided for @imageRejected.
  ///
  /// In tr, this message translates to:
  /// **'Görsel uygunsuz içerik barındırıyor'**
  String get imageRejected;

  /// No description provided for @imageUploadedSuccess.
  ///
  /// In tr, this message translates to:
  /// **'Görsel başarıyla yüklendi'**
  String get imageUploadedSuccess;

  /// No description provided for @adultContentError.
  ///
  /// In tr, this message translates to:
  /// **'Görsel açık yetişkin içeriği barındırıyor'**
  String get adultContentError;

  /// No description provided for @violentContentError.
  ///
  /// In tr, this message translates to:
  /// **'Görsel şiddet içeriği barındırıyor'**
  String get violentContentError;

  /// No description provided for @moderationError.
  ///
  /// In tr, this message translates to:
  /// **'Görsel içeriği doğrulanamadı. Lütfen tekrar deneyin.'**
  String get moderationError;

  /// No description provided for @invitationSentSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Davet başarıyla gönderildi!'**
  String get invitationSentSuccessfully;

  /// No description provided for @accessRevokedSuccessfully.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı erişimi başarıyla iptal edildi!'**
  String get accessRevokedSuccessfully;

  /// Yükleme sırasında bir istisna oluştuğunda gösterilir.
  ///
  /// In tr, this message translates to:
  /// **'Fotoğraf yükleme sırasında hata: {error}'**
  String profileImageUploadError(Object error);

  /// No description provided for @searchCategory.
  ///
  /// In tr, this message translates to:
  /// **'Kategori ara'**
  String get searchCategory;

  /// No description provided for @noSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı satıcı bilginiz bulunmamaktadır'**
  String get noSellerInfo;

  /// No description provided for @noSellerInfoForShop.
  ///
  /// In tr, this message translates to:
  /// **'{shopName} için kayıtlı satıcı bilginiz yok'**
  String noSellerInfoForShop(Object shopName);

  /// No description provided for @shopSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Satıcı Bilgileri'**
  String get shopSellerInfo;

  /// No description provided for @addSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgisi ekle'**
  String get addSellerInfo;

  /// No description provided for @addSellerInfoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı bilgisi'**
  String get addSellerInfoTitle;

  /// No description provided for @selectBrand.
  ///
  /// In tr, this message translates to:
  /// **'Marka seç'**
  String get selectBrand;

  /// No description provided for @searchBrand.
  ///
  /// In tr, this message translates to:
  /// **'Marka ara'**
  String get searchBrand;

  /// No description provided for @youNeedToLogin.
  ///
  /// In tr, this message translates to:
  /// **'Bunu yapmak için oturum açmanız gerekiyor.'**
  String get youNeedToLogin;

  /// No description provided for @modalTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş güvenliği'**
  String get modalTitle;

  /// No description provided for @pleaseSelectAllClothingDetails.
  ///
  /// In tr, this message translates to:
  /// **'Giyim detaylarını seçiniz'**
  String get pleaseSelectAllClothingDetails;

  /// No description provided for @clothingGenderMen.
  ///
  /// In tr, this message translates to:
  /// **'Erkek'**
  String get clothingGenderMen;

  /// No description provided for @clothingGenderWomen.
  ///
  /// In tr, this message translates to:
  /// **'Kadın'**
  String get clothingGenderWomen;

  /// No description provided for @clothingGenderKids.
  ///
  /// In tr, this message translates to:
  /// **'Çocuk'**
  String get clothingGenderKids;

  /// No description provided for @clothingSizeXXS.
  ///
  /// In tr, this message translates to:
  /// **'XXS'**
  String get clothingSizeXXS;

  /// No description provided for @clothingSizeXXL.
  ///
  /// In tr, this message translates to:
  /// **'XXL'**
  String get clothingSizeXXL;

  /// No description provided for @clothingFitLoose.
  ///
  /// In tr, this message translates to:
  /// **'Gevşek'**
  String get clothingFitLoose;

  /// No description provided for @clothingFitOversized.
  ///
  /// In tr, this message translates to:
  /// **'Büyük Beden'**
  String get clothingFitOversized;

  /// No description provided for @clothingTypeWool.
  ///
  /// In tr, this message translates to:
  /// **'Yün'**
  String get clothingTypeWool;

  /// No description provided for @clothingTypeLeather.
  ///
  /// In tr, this message translates to:
  /// **'Deri'**
  String get clothingTypeLeather;

  /// No description provided for @modalSection1Title.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli Ödeme Seçenekleri'**
  String get modalSection1Title;

  /// No description provided for @modalSection1Description.
  ///
  /// In tr, this message translates to:
  /// **'E-CTS, ödeme bilgilerinizin korunmasına kendini adamıştır. Güçlü şifreleme kullanıyoruz ve gizliliğinizi korumak için sistemimizi düzenli olarak gözden geçiriyoruz.'**
  String get modalSection1Description;

  /// No description provided for @modalSection2Title.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli lojistik'**
  String get modalSection2Title;

  /// No description provided for @modalSection2Description1.
  ///
  /// In tr, this message translates to:
  /// **'Tam profesyonel teslimat gerçekleştiriyoruz (hızlı teslimat seçeneği için). Hasarlı veya kayıp paket için tam geri ödeme.'**
  String get modalSection2Description1;

  /// No description provided for @modalSection2Description2.
  ///
  /// In tr, this message translates to:
  /// **'Teslimat garantili, doğru ve zamanında.'**
  String get modalSection2Description2;

  /// No description provided for @modalSection3Title.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli gizlilik'**
  String get modalSection3Title;

  /// No description provided for @modalSection3Description.
  ///
  /// In tr, this message translates to:
  /// **'Gizliliğinizi korumak en büyük önceliğimizdir. Bilgilerinizin güvenli ve tehlikeye atılmamış olarak saklanacağından emin olabilirsiniz. Kişisel bilgilerinizi para karşılığında satmıyoruz ve yalnızca gizlilik ve çerez politikamız kapsamında bilgilerinizi hizmetlerimizi sağlamak ve geliştirmek için kullanacağız.'**
  String get modalSection3Description;

  /// No description provided for @securitySectionTapHint.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazla alışveriş güvenliği detayı görmek için dokunun'**
  String get securitySectionTapHint;

  /// No description provided for @modalSection4Title.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alma Koruması'**
  String get modalSection4Title;

  /// No description provided for @modalSection4Description.
  ///
  /// In tr, this message translates to:
  /// **'Bir sorun çıkarsa, E-CTS her zaman yanınızda olduğundan emin olarak güvenle alışveriş yapın.'**
  String get modalSection4Description;

  /// No description provided for @shoppingSecurityTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alışveriş güvenliği'**
  String get shoppingSecurityTitle;

  /// No description provided for @securityBullet1.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli ödeme seçenekleri'**
  String get securityBullet1;

  /// No description provided for @securityBullet2.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli lojistik'**
  String get securityBullet2;

  /// No description provided for @securityBullet3.
  ///
  /// In tr, this message translates to:
  /// **'Güvenli gizlilik'**
  String get securityBullet3;

  /// No description provided for @securityBullet4.
  ///
  /// In tr, this message translates to:
  /// **'Satın Alma Koruması'**
  String get securityBullet4;

  /// No description provided for @productsSold2.
  ///
  /// In tr, this message translates to:
  /// **'Satılan Ürün'**
  String get productsSold2;

  /// No description provided for @readAll.
  ///
  /// In tr, this message translates to:
  /// **'Devamını oku'**
  String get readAll;

  /// No description provided for @viewInApp.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamada görüntüle'**
  String get viewInApp;

  /// No description provided for @shareWithImage.
  ///
  /// In tr, this message translates to:
  /// **'Özel Görsel ile Paylaş'**
  String get shareWithImage;

  /// No description provided for @copyLink.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantıyı Kopyala'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı panoya kopyalandı!'**
  String get linkCopied;

  /// No description provided for @shareStandard.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Paylaş'**
  String get shareStandard;

  /// No description provided for @shareProductMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürünü nasıl paylaşmak istediğinizi seçin'**
  String get shareProductMessage;

  /// No description provided for @scanToView.
  ///
  /// In tr, this message translates to:
  /// **'Görüntülemek için tara'**
  String get scanToView;

  /// No description provided for @minutes.
  ///
  /// In tr, this message translates to:
  /// **'dakika'**
  String get minutes;

  /// No description provided for @totalListings.
  ///
  /// In tr, this message translates to:
  /// **'Listelemeler'**
  String get totalListings;

  /// No description provided for @tapToVisitYourShop.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızı ziyaret etmek için dokunun'**
  String get tapToVisitYourShop;

  /// No description provided for @shopDisapprovedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza başvurunuz reddedildi.'**
  String get shopDisapprovedMessage;

  /// Tüm yorumları görmek için düğme metni ve toplam sayısı
  ///
  /// In tr, this message translates to:
  /// **'Tüm Yorumları Gör {count}'**
  String seeAllReviewsWithCount(Object count);

  /// No description provided for @moreColorOptions.
  ///
  /// In tr, this message translates to:
  /// **'Ürünün fazladan renk seçeneği mevcut ise eklemek ister misiniz?'**
  String get moreColorOptions;

  /// No description provided for @colorOptionWarning.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen renk seçenekleri için lütfen miktar belirtiniz ve bir resim yükleyiniz'**
  String get colorOptionWarning;

  /// No description provided for @okay.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get okay;

  /// No description provided for @waistSize.
  ///
  /// In tr, this message translates to:
  /// **'Bel'**
  String get waistSize;

  /// No description provided for @heightSize.
  ///
  /// In tr, this message translates to:
  /// **'Yükseklik'**
  String get heightSize;

  /// No description provided for @completeProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profili Tamamlayın'**
  String get completeProfile;

  /// No description provided for @pleaseFillMissingFields.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen tüm alanları doldurunuz'**
  String get pleaseFillMissingFields;

  /// Ürünün kaç kişinin sepetinde olduğunu gösterir
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =0{Sepet boş} other{{count} kişinin sepetinde!}}'**
  String cartCount2(num count);

  /// Ürünün kaç kişinin favorilerinde olduğunu gösterir
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =0{Favoriler boş} other{{count} kişinin favorilerinde!}}'**
  String favoriteCount2(num count);

  /// Bu ürünü kaç kişinin satın aldığını gösterir
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =0{Satın alan yok} one{{count} kişi satın aldı!} other{{count} kişi satın aldı!}}'**
  String purchaseCount2(num count);

  /// No description provided for @genericNotificationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Bildirim'**
  String get genericNotificationTitle;

  /// No description provided for @genericNotificationBody.
  ///
  /// In tr, this message translates to:
  /// **'Yeni bir bildiriminiz var!'**
  String get genericNotificationBody;

  /// No description provided for @productOutOfStockTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Stoğu Tükendi ⚠️'**
  String get productOutOfStockTitle;

  /// No description provided for @productOutOfStockBody.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz stokta kalmadı.'**
  String get productOutOfStockBody;

  /// No description provided for @shopProductOutOfStockTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Ürünü Stoğu Tükendi ⚠️'**
  String get shopProductOutOfStockTitle;

  /// No description provided for @shopProductOutOfStockBody.
  ///
  /// In tr, this message translates to:
  /// **'Mağanızdaki bir ürün stokta kalmadı.'**
  String get shopProductOutOfStockBody;

  /// No description provided for @boostExpiredTitle.
  ///
  /// In tr, this message translates to:
  /// **'Boost Süresi Doldu ⚠️'**
  String get boostExpiredTitle;

  /// No description provided for @boostExpiredBody.
  ///
  /// In tr, this message translates to:
  /// **'Öne çıkarılan ürünün süresi doldu.'**
  String get boostExpiredBody;

  /// No description provided for @shopProductSoldTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Ürünü Satıldı! 🎉'**
  String get shopProductSoldTitle;

  /// No description provided for @shopProductSoldBody.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızdaki ürün satıldı!'**
  String get shopProductSoldBody;

  /// No description provided for @shipmentStatusUpdatedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Gönderi Durumu Güncellendi! ✅'**
  String get shipmentStatusUpdatedTitle;

  /// No description provided for @shipmentStatusUpdatedBody.
  ///
  /// In tr, this message translates to:
  /// **'Gönderi durumunuz güncellendi!'**
  String get shipmentStatusUpdatedBody;

  /// No description provided for @deleteSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilenleri sil'**
  String get deleteSelected;

  /// No description provided for @noItemsSelected.
  ///
  /// In tr, this message translates to:
  /// **'Hiç ürün seçilmedi'**
  String get noItemsSelected;

  /// No description provided for @pleaseSelectItemsToCheckout.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen ödeme için ürün seçin'**
  String get pleaseSelectItemsToCheckout;

  /// No description provided for @itemsRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler başarıyla kaldırıldı'**
  String get itemsRemoved;

  /// No description provided for @proceedToCheckout.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeye Geç'**
  String get proceedToCheckout;

  /// No description provided for @startAddingItems.
  ///
  /// In tr, this message translates to:
  /// **'Sepetinize ürün eklemeye başlayın'**
  String get startAddingItems;

  /// No description provided for @browseProducts.
  ///
  /// In tr, this message translates to:
  /// **'Ürünlere Gözat'**
  String get browseProducts;

  /// No description provided for @youGotDiscount.
  ///
  /// In tr, this message translates to:
  /// **'%{percentage} indirim kazandınız!'**
  String youGotDiscount(int percentage);

  /// No description provided for @buyForDiscount.
  ///
  /// In tr, this message translates to:
  /// **'{threshold} ürün alın %{percentage} indirim kazanın'**
  String buyForDiscount(int threshold, int percentage);

  /// No description provided for @maxAllowedQuantity.
  ///
  /// In tr, this message translates to:
  /// **'İzin verilen maksimum miktar: {max}'**
  String maxAllowedQuantity(int max);

  /// No description provided for @errorRemovingFavorite.
  ///
  /// In tr, this message translates to:
  /// **'Favori kaldırılırken hata'**
  String get errorRemovingFavorite;

  /// No description provided for @transferFailed.
  ///
  /// In tr, this message translates to:
  /// **'Aktarma başarısız'**
  String get transferFailed;

  /// No description provided for @errorTransferringItem.
  ///
  /// In tr, this message translates to:
  /// **'Ürün aktarılırken hata'**
  String get errorTransferringItem;

  /// No description provided for @maximumBasketLimit.
  ///
  /// In tr, this message translates to:
  /// **'Maksimum sepet limitine ulaşıldı'**
  String get maximumBasketLimit;

  /// No description provided for @errorCreatingBasket.
  ///
  /// In tr, this message translates to:
  /// **'Sepet oluşturulurken hata'**
  String get errorCreatingBasket;

  /// No description provided for @errorDeletingBasket.
  ///
  /// In tr, this message translates to:
  /// **'Sepet silinirken hata'**
  String get errorDeletingBasket;

  /// No description provided for @failedToLoadFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler yüklenemedi. Lütfen tekrar deneyin.'**
  String get failedToLoadFavorites;

  /// No description provided for @productsRemovedFromFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Ürünler favorilerden kaldırıldı'**
  String get productsRemovedFromFavorites;

  /// No description provided for @errorRemovingFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler kaldırılırken hata'**
  String get errorRemovingFavorites;

  /// No description provided for @serviceTemporarilyUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Hizmet geçici olarak kullanılamıyor'**
  String get serviceTemporarilyUnavailable;

  /// No description provided for @failedToUpdateFavorites.
  ///
  /// In tr, this message translates to:
  /// **'Favoriler güncellenemedi'**
  String get failedToUpdateFavorites;

  /// No description provided for @isAlreadyInCart.
  ///
  /// In tr, this message translates to:
  /// **'zaten sepette'**
  String get isAlreadyInCart;

  /// No description provided for @isNoLongerAvailable.
  ///
  /// In tr, this message translates to:
  /// **'artık mevcut değil'**
  String get isNoLongerAvailable;

  /// No description provided for @profileLoadingError.
  ///
  /// In tr, this message translates to:
  /// **'Profiliniz yüklenemedi'**
  String get profileLoadingError;

  /// No description provided for @profileNetworkError.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bağlantınızı kontrol edip tekrar deneyin'**
  String get profileNetworkError;

  /// No description provided for @profileUnknownError.
  ///
  /// In tr, this message translates to:
  /// **'Bir şeyler ters gitti. Lütfen tekrar deneyin'**
  String get profileUnknownError;

  /// No description provided for @errorNoConnection.
  ///
  /// In tr, this message translates to:
  /// **'İnternet bağlantısı yok. Lütfen ağınızı kontrol edip tekrar deneyin.'**
  String get errorNoConnection;

  /// No description provided for @errorTimeout.
  ///
  /// In tr, this message translates to:
  /// **'İstek zaman aşımına uğradı. Lütfen bağlantınızı kontrol edip tekrar deneyin.'**
  String get errorTimeout;

  /// No description provided for @scanQRCode.
  ///
  /// In tr, this message translates to:
  /// **'QR Kod Tara'**
  String get scanQRCode;

  /// No description provided for @scanBuyerQRToVerify.
  ///
  /// In tr, this message translates to:
  /// **'Teslimatı doğrulamak için alıcının sipariş fişindeki QR kodunu tarayın'**
  String get scanBuyerQRToVerify;

  /// No description provided for @verifyingQRCode.
  ///
  /// In tr, this message translates to:
  /// **'QR kod doğrulanıyor...'**
  String get verifyingQRCode;

  /// No description provided for @positionQRInFrame.
  ///
  /// In tr, this message translates to:
  /// **'Taramak için QR kodu çerçeve içine yerleştirin'**
  String get positionQRInFrame;

  /// No description provided for @skipQRVerification.
  ///
  /// In tr, this message translates to:
  /// **'QR Doğrulamayı Atla'**
  String get skipQRVerification;

  /// No description provided for @skipQRVerificationMessage.
  ///
  /// In tr, this message translates to:
  /// **'QR doğrulamayı atlamak istediğinizden emin misiniz? Bu yalnızca alıcı QR kodunu gösteremiyorsa yapılmalıdır.'**
  String get skipQRVerificationMessage;

  /// No description provided for @skipAndContinue.
  ///
  /// In tr, this message translates to:
  /// **'Atla ve Devam Et'**
  String get skipAndContinue;

  /// No description provided for @qrVerifiedDeliveryConfirmed.
  ///
  /// In tr, this message translates to:
  /// **'QR doğrulandı! Teslimat başarıyla onaylandı'**
  String get qrVerifiedDeliveryConfirmed;

  /// No description provided for @qrVerificationFailed.
  ///
  /// In tr, this message translates to:
  /// **'QR doğrulama başarısız'**
  String get qrVerificationFailed;

  /// No description provided for @invalidQRCode.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz QR kod'**
  String get invalidQRCode;

  /// No description provided for @qrCodeMismatch.
  ///
  /// In tr, this message translates to:
  /// **'QR kod bu siparişle eşleşmiyor'**
  String get qrCodeMismatch;

  /// No description provided for @stopConfirmedMovingNext.
  ///
  /// In tr, this message translates to:
  /// **'Durak onaylandı. Sonraki durağa geçiliyor.'**
  String get stopConfirmedMovingNext;

  /// No description provided for @iAccept.
  ///
  /// In tr, this message translates to:
  /// **'Kabul ediyorum'**
  String get iAccept;

  /// No description provided for @distanceSellingAgreement.
  ///
  /// In tr, this message translates to:
  /// **'Mesafeli Satış Sözleşmesi'**
  String get distanceSellingAgreement;

  /// No description provided for @personalData.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel Veriler'**
  String get personalData;

  /// No description provided for @pleaseLoginToSubmitQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Soru göndermek için lütfen giriş yapın'**
  String get pleaseLoginToSubmitQuestion;

  /// No description provided for @cannotEditProduct.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Düzenlenemiyor'**
  String get cannotEditProduct;

  /// No description provided for @cannotEditProductMessage.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün bir kampanyaya, pakete dahil olduğu veya aktif satış tercihleri bulunduğu için düzenlenemiyor. Lütfen önce ürünü kampanyadan/paketten çıkarın veya satış tercihlerini kaldırın.'**
  String get cannotEditProductMessage;

  /// No description provided for @removeDiscountToCreateBundle.
  ///
  /// In tr, this message translates to:
  /// **'Bu üründe aktif indirim var. Pakete eklemek için önce indirimi kaldırın.'**
  String get removeDiscountToCreateBundle;

  /// No description provided for @productInBundleCannotAddToCampaign.
  ///
  /// In tr, this message translates to:
  /// **'Bu ürün bir paketin parçası. Kampanyaya dahil etmek için önce paketten çıkarın.'**
  String get productInBundleCannotAddToCampaign;

  /// No description provided for @shopNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Mağaza Bildirimleri'**
  String get shopNotifications;

  /// No description provided for @noShopNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bildirim yok'**
  String get noShopNotifications;

  /// No description provided for @noShopNotificationsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Mağazanızla ilgili bildirimler burada görünecek'**
  String get noShopNotificationsDesc;

  /// No description provided for @errorLoadingNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler yüklenemedi'**
  String get errorLoadingNotifications;

  /// No description provided for @justNow.
  ///
  /// In tr, this message translates to:
  /// **'Az önce'**
  String get justNow;

  /// No description provided for @productApplications.
  ///
  /// In tr, this message translates to:
  /// **'Ürün Başvuruları'**
  String get productApplications;

  /// No description provided for @skip.
  ///
  /// In tr, this message translates to:
  /// **'Atla'**
  String get skip;

  /// No description provided for @profileCompletionMessage.
  ///
  /// In tr, this message translates to:
  /// **'Kişiselleştirilmiş deneyim için bilgilerinizi ekleyin'**
  String get profileCompletionMessage;

  /// No description provided for @agreementRequired.
  ///
  /// In tr, this message translates to:
  /// **'Sözleşme Onayı Gerekli'**
  String get agreementRequired;

  /// No description provided for @agreementModalDescription.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı kullanmaya devam etmek için lütfen şartlarımızı ve sözleşmelerimizi inceleyin ve kabul edin.'**
  String get agreementModalDescription;

  /// No description provided for @iHaveReadAndAccept.
  ///
  /// In tr, this message translates to:
  /// **'Tüm sözleşmeleri okudum ve kabul ediyorum'**
  String get iHaveReadAndAccept;

  /// No description provided for @acceptAndContinue.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Et ve Devam Et'**
  String get acceptAndContinue;

  /// No description provided for @appleLoginButton.
  ///
  /// In tr, this message translates to:
  /// **'Apple ile Giriş Yap'**
  String get appleLoginButton;

  /// No description provided for @registerWithApple.
  ///
  /// In tr, this message translates to:
  /// **'Apple ile Kayıt Ol'**
  String get registerWithApple;

  /// No description provided for @whatsYourName.
  ///
  /// In tr, this message translates to:
  /// **'Adınız nedir?'**
  String get whatsYourName;

  /// No description provided for @nameNeededForOrders.
  ///
  /// In tr, this message translates to:
  /// **'Sipariş teslimatı için adınıza ihtiyacımız var'**
  String get nameNeededForOrders;

  /// No description provided for @firstName.
  ///
  /// In tr, this message translates to:
  /// **'Ad'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In tr, this message translates to:
  /// **'Soyad'**
  String get lastName;

  /// No description provided for @firstNameHint.
  ///
  /// In tr, this message translates to:
  /// **'Adınızı girin'**
  String get firstNameHint;

  /// No description provided for @lastNameHint.
  ///
  /// In tr, this message translates to:
  /// **'Soyadınızı girin'**
  String get lastNameHint;

  /// No description provided for @firstNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Ad gerekli'**
  String get firstNameRequired;

  /// No description provided for @lastNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Soyad gerekli'**
  String get lastNameRequired;

  /// No description provided for @nameTooShort.
  ///
  /// In tr, this message translates to:
  /// **'İsim çok kısa'**
  String get nameTooShort;

  /// No description provided for @nameRequiredMessage.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için lütfen adınızı girin.'**
  String get nameRequiredMessage;

  /// No description provided for @bundleNoLongerAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Paket artık mevcut değil. Normal fiyat uygulanacak.'**
  String get bundleNoLongerAvailable;

  /// No description provided for @bundleNoLongerAvailableTitle.
  ///
  /// In tr, this message translates to:
  /// **'Paket Mevcut Değil'**
  String get bundleNoLongerAvailableTitle;

  /// No description provided for @bundleStatus.
  ///
  /// In tr, this message translates to:
  /// **'Paket Durumu'**
  String get bundleStatus;

  /// No description provided for @bundleWasPrice.
  ///
  /// In tr, this message translates to:
  /// **'Önceki (Paket)'**
  String get bundleWasPrice;

  /// No description provided for @nowRegularPrice.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi (Normal)'**
  String get nowRegularPrice;

  /// No description provided for @regularPrice.
  ///
  /// In tr, this message translates to:
  /// **'Normal Fiyat'**
  String get regularPrice;

  /// No description provided for @adServiceTemporarilyOff.
  ///
  /// In tr, this message translates to:
  /// **'Servis Geçici Olarak Kapalı'**
  String get adServiceTemporarilyOff;

  /// No description provided for @adServiceDisabledMessage.
  ///
  /// In tr, this message translates to:
  /// **'Reklam başvuruları geçici olarak durdurulmuştur. Devam eden reklamlarınız etkilenmeyecektir. Lütfen daha sonra tekrar deneyin.'**
  String get adServiceDisabledMessage;

  /// No description provided for @boostServiceTemporarilyOff.
  ///
  /// In tr, this message translates to:
  /// **'Servis Geçici Olarak Kapalı'**
  String get boostServiceTemporarilyOff;

  /// No description provided for @boostServiceDisabledMessage.
  ///
  /// In tr, this message translates to:
  /// **'Ürün boost işlemleri geçici olarak durdurulmuştur. Aktif boostlarınız çalışmaya devam edecektir. Lütfen daha sonra tekrar deneyin.'**
  String get boostServiceDisabledMessage;

  /// No description provided for @subSubcategoryBrakeComponents.
  ///
  /// In tr, this message translates to:
  /// **'Fren Parçaları'**
  String get subSubcategoryBrakeComponents;

  /// No description provided for @subSubcategoryTransmissionParts.
  ///
  /// In tr, this message translates to:
  /// **'Şanzıman Parçaları'**
  String get subSubcategoryTransmissionParts;

  /// No description provided for @subSubcategoryExhaustSystems.
  ///
  /// In tr, this message translates to:
  /// **'Egzoz Sistemleri'**
  String get subSubcategoryExhaustSystems;

  /// No description provided for @subSubcategoryFiltersAuto.
  ///
  /// In tr, this message translates to:
  /// **'Filtreler'**
  String get subSubcategoryFiltersAuto;

  /// No description provided for @subSubcategoryBeltsHoses.
  ///
  /// In tr, this message translates to:
  /// **'Kayış ve Hortumlar'**
  String get subSubcategoryBeltsHoses;

  /// No description provided for @subSubcategoryCarAudio.
  ///
  /// In tr, this message translates to:
  /// **'Araç Ses Sistemleri'**
  String get subSubcategoryCarAudio;

  /// No description provided for @subSubcategoryDashCams.
  ///
  /// In tr, this message translates to:
  /// **'Araç Kameraları'**
  String get subSubcategoryDashCams;

  /// No description provided for @subSubcategoryBluetoothAdapters.
  ///
  /// In tr, this message translates to:
  /// **'Bluetooth Adaptörleri'**
  String get subSubcategoryBluetoothAdapters;

  /// No description provided for @subSubcategoryBackupCameras.
  ///
  /// In tr, this message translates to:
  /// **'Geri Görüş Kameraları'**
  String get subSubcategoryBackupCameras;

  /// No description provided for @subSubcategoryMotorOil.
  ///
  /// In tr, this message translates to:
  /// **'Motor Yağı'**
  String get subSubcategoryMotorOil;

  /// No description provided for @subSubcategoryCarCleaners.
  ///
  /// In tr, this message translates to:
  /// **'Araç Temizleyicileri'**
  String get subSubcategoryCarCleaners;

  /// No description provided for @subSubcategoryMaintenanceTools.
  ///
  /// In tr, this message translates to:
  /// **'Bakım Aletleri'**
  String get subSubcategoryMaintenanceTools;

  /// No description provided for @subSubcategoryFluidsAuto.
  ///
  /// In tr, this message translates to:
  /// **'Sıvılar'**
  String get subSubcategoryFluidsAuto;

  /// No description provided for @subSubcategoryTires.
  ///
  /// In tr, this message translates to:
  /// **'Lastikler'**
  String get subSubcategoryTires;

  /// No description provided for @subSubcategoryWheels.
  ///
  /// In tr, this message translates to:
  /// **'Jantlar'**
  String get subSubcategoryWheels;

  /// No description provided for @subSubcategoryTireAccessories.
  ///
  /// In tr, this message translates to:
  /// **'Lastik Aksesuarları'**
  String get subSubcategoryTireAccessories;

  /// No description provided for @subSubcategoryWheelCovers.
  ///
  /// In tr, this message translates to:
  /// **'Jant Kapakları'**
  String get subSubcategoryWheelCovers;

  /// No description provided for @subSubcategoryTirePressureMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Lastik Basınç Monitörleri'**
  String get subSubcategoryTirePressureMonitors;

  /// No description provided for @subSubcategorySeatCovers.
  ///
  /// In tr, this message translates to:
  /// **'Koltuk Kılıfları'**
  String get subSubcategorySeatCovers;

  /// No description provided for @subSubcategoryFloorMats.
  ///
  /// In tr, this message translates to:
  /// **'Paspaslar'**
  String get subSubcategoryFloorMats;

  /// No description provided for @subSubcategorySteeringWheelCovers.
  ///
  /// In tr, this message translates to:
  /// **'Direksiyon Kılıfları'**
  String get subSubcategorySteeringWheelCovers;

  /// No description provided for @subSubcategoryAirFresheners.
  ///
  /// In tr, this message translates to:
  /// **'Oto Kokuları'**
  String get subSubcategoryAirFresheners;

  /// No description provided for @subSubcategoryInteriorOrganizers.
  ///
  /// In tr, this message translates to:
  /// **'İç Mekan Düzenleyicileri'**
  String get subSubcategoryInteriorOrganizers;

  /// No description provided for @subSubcategorySunshades.
  ///
  /// In tr, this message translates to:
  /// **'Güneşlikler'**
  String get subSubcategorySunshades;

  /// No description provided for @subSubcategoryCarCovers.
  ///
  /// In tr, this message translates to:
  /// **'Araç Örtüleri'**
  String get subSubcategoryCarCovers;

  /// No description provided for @subSubcategoryRoofRacks.
  ///
  /// In tr, this message translates to:
  /// **'Tavan Bagajları'**
  String get subSubcategoryRoofRacks;

  /// No description provided for @subSubcategoryRunningBoards.
  ///
  /// In tr, this message translates to:
  /// **'Kapı Basamakları'**
  String get subSubcategoryRunningBoards;

  /// No description provided for @subSubcategoryMudFlaps.
  ///
  /// In tr, this message translates to:
  /// **'Çamurluklar'**
  String get subSubcategoryMudFlaps;

  /// No description provided for @subSubcategoryLicensePlateFrames.
  ///
  /// In tr, this message translates to:
  /// **'Plaka Çerçeveleri'**
  String get subSubcategoryLicensePlateFrames;

  /// No description provided for @subSubcategoryDecals.
  ///
  /// In tr, this message translates to:
  /// **'Çıkartmalar'**
  String get subSubcategoryDecals;

  /// No description provided for @subSubcategoryJumpStarters.
  ///
  /// In tr, this message translates to:
  /// **'Akü Takviye Cihazları'**
  String get subSubcategoryJumpStarters;

  /// No description provided for @subSubcategoryTireGauges.
  ///
  /// In tr, this message translates to:
  /// **'Lastik Basınç Ölçerler'**
  String get subSubcategoryTireGauges;

  /// No description provided for @subSubcategoryMechanicsTools.
  ///
  /// In tr, this message translates to:
  /// **'Mekanik Aletleri'**
  String get subSubcategoryMechanicsTools;

  /// No description provided for @subSubcategoryCarJacks.
  ///
  /// In tr, this message translates to:
  /// **'Araba Krikoları'**
  String get subSubcategoryCarJacks;

  /// No description provided for @subSubcategoryEmergencyKitsAuto.
  ///
  /// In tr, this message translates to:
  /// **'Acil Durum Setleri'**
  String get subSubcategoryEmergencyKitsAuto;

  /// No description provided for @subSubcategoryMotorcyclePartsGeneral.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Parçaları'**
  String get subSubcategoryMotorcyclePartsGeneral;

  /// No description provided for @subSubcategoryMotorcycleAccessoriesGeneral.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Aksesuarları'**
  String get subSubcategoryMotorcycleAccessoriesGeneral;

  /// No description provided for @subSubcategoryMotorcycleGear.
  ///
  /// In tr, this message translates to:
  /// **'Motosiklet Ekipmanları'**
  String get subSubcategoryMotorcycleGear;

  /// No description provided for @subSubcategoryHelmets.
  ///
  /// In tr, this message translates to:
  /// **'Kasklar'**
  String get subSubcategoryHelmets;

  /// No description provided for @subSubcategoryProtectiveClothing.
  ///
  /// In tr, this message translates to:
  /// **'Koruyucu Giysi'**
  String get subSubcategoryProtectiveClothing;

  /// No description provided for @subSubcategoryBVitamins.
  ///
  /// In tr, this message translates to:
  /// **'B Vitaminleri'**
  String get subSubcategoryBVitamins;

  /// No description provided for @subSubcategoryHerbalSupplements.
  ///
  /// In tr, this message translates to:
  /// **'Bitkisel Takviyeler'**
  String get subSubcategoryHerbalSupplements;

  /// No description provided for @subSubcategoryMedicalScales.
  ///
  /// In tr, this message translates to:
  /// **'Medikal Tartılar'**
  String get subSubcategoryMedicalScales;

  /// No description provided for @subSubcategorySafetyEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik Ekipmanları'**
  String get subSubcategorySafetyEquipment;

  /// No description provided for @subSubcategoryHomeGymEquipment.
  ///
  /// In tr, this message translates to:
  /// **'Ev Spor Aletleri'**
  String get subSubcategoryHomeGymEquipment;

  /// No description provided for @subSubcategoryCardioMachines.
  ///
  /// In tr, this message translates to:
  /// **'Kardiyo Makineleri'**
  String get subSubcategoryCardioMachines;

  /// No description provided for @subSubcategoryWeightsDumbbells.
  ///
  /// In tr, this message translates to:
  /// **'Ağırlıklar ve Dambıllar'**
  String get subSubcategoryWeightsDumbbells;

  /// No description provided for @subSubcategoryResistanceBands.
  ///
  /// In tr, this message translates to:
  /// **'Direnç Bantları'**
  String get subSubcategoryResistanceBands;

  /// No description provided for @subSubcategoryYogaMats.
  ///
  /// In tr, this message translates to:
  /// **'Yoga Matları'**
  String get subSubcategoryYogaMats;

  /// No description provided for @subSubcategoryExerciseBikes.
  ///
  /// In tr, this message translates to:
  /// **'Egzersiz Bisikletleri'**
  String get subSubcategoryExerciseBikes;

  /// No description provided for @subSubcategorySmartScales.
  ///
  /// In tr, this message translates to:
  /// **'Akıllı Tartılar'**
  String get subSubcategorySmartScales;

  /// No description provided for @subSubcategoryHeartRateMonitors.
  ///
  /// In tr, this message translates to:
  /// **'Kalp Atış Hızı Monitörleri'**
  String get subSubcategoryHeartRateMonitors;

  /// No description provided for @subSubcategorySleepTrackers.
  ///
  /// In tr, this message translates to:
  /// **'Uyku Takipçileri'**
  String get subSubcategorySleepTrackers;

  /// No description provided for @subSubcategoryHealthApps.
  ///
  /// In tr, this message translates to:
  /// **'Sağlık Uygulamaları'**
  String get subSubcategoryHealthApps;

  /// No description provided for @subSubcategoryMobilityAidsGeneral.
  ///
  /// In tr, this message translates to:
  /// **'Hareket Yardımcıları'**
  String get subSubcategoryMobilityAidsGeneral;

  /// No description provided for @subSubcategoryGrabBars.
  ///
  /// In tr, this message translates to:
  /// **'Tutunma Barları'**
  String get subSubcategoryGrabBars;

  /// No description provided for @subSubcategorySeatCushions.
  ///
  /// In tr, this message translates to:
  /// **'Oturma Minderleri'**
  String get subSubcategorySeatCushions;

  /// No description provided for @subSubcategoryDailyLivingAids.
  ///
  /// In tr, this message translates to:
  /// **'Günlük Yaşam Yardımcıları'**
  String get subSubcategoryDailyLivingAids;

  /// No description provided for @subSubcategoryMassageTools.
  ///
  /// In tr, this message translates to:
  /// **'Masaj Aletleri'**
  String get subSubcategoryMassageTools;

  /// No description provided for @subSubcategoryAcupuncture.
  ///
  /// In tr, this message translates to:
  /// **'Akupunktur'**
  String get subSubcategoryAcupuncture;

  /// No description provided for @subSubcategoryNaturalRemedies.
  ///
  /// In tr, this message translates to:
  /// **'Doğal İlaçlar'**
  String get subSubcategoryNaturalRemedies;

  /// No description provided for @subSubcategoryOralCare.
  ///
  /// In tr, this message translates to:
  /// **'Ağız Bakımı'**
  String get subSubcategoryOralCare;

  /// No description provided for @subSubcategoryIncontinenceCare.
  ///
  /// In tr, this message translates to:
  /// **'İdrar Kaçırma Bakımı'**
  String get subSubcategoryIncontinenceCare;

  /// No description provided for @subSubcategoryHearingAids.
  ///
  /// In tr, this message translates to:
  /// **'İşitme Cihazları'**
  String get subSubcategoryHearingAids;

  /// No description provided for @subSubcategoryVisionCare.
  ///
  /// In tr, this message translates to:
  /// **'Göz Bakımı'**
  String get subSubcategoryVisionCare;

  /// No description provided for @subSubcategorySkinCareHealth.
  ///
  /// In tr, this message translates to:
  /// **'Cilt Bakımı'**
  String get subSubcategorySkinCareHealth;

  /// No description provided for @subSubcategoryGPSAndNavigation.
  ///
  /// In tr, this message translates to:
  /// **'GPS & Navigasyon'**
  String get subSubcategoryGPSAndNavigation;

  /// No description provided for @couponsAndBenefits.
  ///
  /// In tr, this message translates to:
  /// **'Kuponlar ve Avantajlar'**
  String get couponsAndBenefits;

  /// No description provided for @freeShipping.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz Kargo'**
  String get freeShipping;

  /// No description provided for @discountCoupons.
  ///
  /// In tr, this message translates to:
  /// **'İndirim Kuponları'**
  String get discountCoupons;

  /// No description provided for @useFreeShipping.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz Kargo Kullan'**
  String get useFreeShipping;

  /// No description provided for @freeShippingDescription.
  ///
  /// In tr, this message translates to:
  /// **'Kargo ücretiniz alınmayacak'**
  String get freeShippingDescription;

  /// No description provided for @noCoupon.
  ///
  /// In tr, this message translates to:
  /// **'Kupon Yok'**
  String get noCoupon;

  /// No description provided for @proceedWithoutDiscount.
  ///
  /// In tr, this message translates to:
  /// **'İndirimsiz devam et'**
  String get proceedWithoutDiscount;

  /// No description provided for @willDeduct.
  ///
  /// In tr, this message translates to:
  /// **'İndirim'**
  String get willDeduct;

  /// No description provided for @discountCouponDesc.
  ///
  /// In tr, this message translates to:
  /// **'İndirim kuponu'**
  String get discountCouponDesc;

  /// No description provided for @noCouponsAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Kullanılabilir kupon yok'**
  String get noCouponsAvailable;

  /// No description provided for @coupon.
  ///
  /// In tr, this message translates to:
  /// **'Kupon'**
  String get coupon;

  /// No description provided for @addCouponOrBenefit.
  ///
  /// In tr, this message translates to:
  /// **'Kupon veya avantaj ekle'**
  String get addCouponOrBenefit;

  /// No description provided for @couponApplied.
  ///
  /// In tr, this message translates to:
  /// **'Kupon uygulandı'**
  String get couponApplied;

  /// No description provided for @freeShippingApplied.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz kargo uygulandı'**
  String get freeShippingApplied;

  /// No description provided for @youSave.
  ///
  /// In tr, this message translates to:
  /// **'Kazancınız'**
  String get youSave;

  /// No description provided for @expiresIn.
  ///
  /// In tr, this message translates to:
  /// **'Geçerlilik'**
  String get expiresIn;

  /// No description provided for @expired.
  ///
  /// In tr, this message translates to:
  /// **'Süresi doldu'**
  String get expired;

  /// No description provided for @applied.
  ///
  /// In tr, this message translates to:
  /// **'uygulandı'**
  String get applied;

  /// No description provided for @couponAlreadyUsed.
  ///
  /// In tr, this message translates to:
  /// **'Bu kupon zaten kullanılmış'**
  String get couponAlreadyUsed;

  /// No description provided for @couponExpired.
  ///
  /// In tr, this message translates to:
  /// **'Bu kuponun süresi dolmuş'**
  String get couponExpired;

  /// No description provided for @couponNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Kupon bulunamadı'**
  String get couponNotFound;

  /// No description provided for @freeShippingAlreadyUsed.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz kargo zaten kullanılmış'**
  String get freeShippingAlreadyUsed;

  /// No description provided for @freeShippingExpired.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz kargo süresı dolmuş'**
  String get freeShippingExpired;

  /// No description provided for @stockIssue.
  ///
  /// In tr, this message translates to:
  /// **'Stok sorunu. Lütfen tekrar deneyin.'**
  String get stockIssue;

  /// No description provided for @couponDiscount.
  ///
  /// In tr, this message translates to:
  /// **'Kupon İndirimi'**
  String get couponDiscount;

  /// No description provided for @freeShippingBenefit.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz Kargo Avantajı'**
  String get freeShippingBenefit;

  /// No description provided for @youSaved.
  ///
  /// In tr, this message translates to:
  /// **'Tasarrufunuz'**
  String get youSaved;

  /// No description provided for @youHaveACoupon.
  ///
  /// In tr, this message translates to:
  /// **'🎉 Kuponunuz var!'**
  String get youHaveACoupon;

  /// No description provided for @couponWaitingForYou.
  ///
  /// In tr, this message translates to:
  /// **'Sepetinizde sizi bekleyen özel bir indirim var!'**
  String get couponWaitingForYou;

  /// No description provided for @expressDisabledWithBenefit.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz kargo avantajı ile ekspres teslimat seçilemez'**
  String get expressDisabledWithBenefit;

  /// No description provided for @myCouponsAndBenefits.
  ///
  /// In tr, this message translates to:
  /// **'Kuponlarım ve Avantajlarım'**
  String get myCouponsAndBenefits;

  /// No description provided for @coupons.
  ///
  /// In tr, this message translates to:
  /// **'Kuponlar'**
  String get coupons;

  /// No description provided for @activeCoupons.
  ///
  /// In tr, this message translates to:
  /// **'Aktif'**
  String get activeCoupons;

  /// No description provided for @usedCoupons.
  ///
  /// In tr, this message translates to:
  /// **'Kullanılmış'**
  String get usedCoupons;

  /// No description provided for @noCouponsOrBenefits.
  ///
  /// In tr, this message translates to:
  /// **'Kupon veya Avantaj Yok'**
  String get noCouponsOrBenefits;

  /// No description provided for @noCouponsOrBenefitsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz aktif kuponunuz veya avantajınız yok. Daha sonra tekrar kontrol edin!'**
  String get noCouponsOrBenefitsDescription;

  /// No description provided for @limitedSearchMode.
  ///
  /// In tr, this message translates to:
  /// **'Gelişmiş arama bakımı devam etmektedir. Lütfen birkaç dakika sonra tekrar deneyin.'**
  String get limitedSearchMode;

  /// No description provided for @productArchivedByAdmin.
  ///
  /// In tr, this message translates to:
  /// **'Ürününüz Admin Tarafından Durduruldu. Ayrıntılar için dokunun.'**
  String get productArchivedByAdmin;

  /// No description provided for @noUsedCouponsOrBenefits.
  ///
  /// In tr, this message translates to:
  /// **'Kullanılmış Kupon veya Avantaj Yok'**
  String get noUsedCouponsOrBenefits;

  /// No description provided for @noUsedCouponsOrBenefitsDescription.
  ///
  /// In tr, this message translates to:
  /// **'Henüz hiç kupon veya avantaj kullanmadınız.'**
  String get noUsedCouponsOrBenefitsDescription;

  /// No description provided for @validUntil.
  ///
  /// In tr, this message translates to:
  /// **'Son kullanma tarihi'**
  String get validUntil;

  /// No description provided for @noExpiry.
  ///
  /// In tr, this message translates to:
  /// **'Son kullanma tarihi yok'**
  String get noExpiry;

  /// No description provided for @usedOn.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım tarihi'**
  String get usedOn;

  /// No description provided for @enjoyYourGift.
  ///
  /// In tr, this message translates to:
  /// **'Hediyenizin Keyfini Çıkarın'**
  String get enjoyYourGift;

  /// No description provided for @freeShippingBenefitDescription.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki siparişiniz için ücretsiz kargo'**
  String get freeShippingBenefitDescription;

  /// No description provided for @couponsErrorLoadingData.
  ///
  /// In tr, this message translates to:
  /// **'Veri Yüklenirken Hata'**
  String get couponsErrorLoadingData;

  /// No description provided for @couponsTryAgainLater.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen daha sonra tekrar deneyin.'**
  String get couponsTryAgainLater;

  /// No description provided for @pleaseSelectColor.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir renk seçin'**
  String get pleaseSelectColor;

  /// No description provided for @pleaseSelectAnOption.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir seçenek seçin'**
  String get pleaseSelectAnOption;

  /// No description provided for @pleaseEnterValidDimensions.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen geçerli ölçüler girin'**
  String get pleaseEnterValidDimensions;

  /// No description provided for @invalidIban.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz IBAN.'**
  String get invalidIban;

  /// No description provided for @minimumCartTotal.
  ///
  /// In tr, this message translates to:
  /// **'Min. sepet tutarı: {amount} TL'**
  String minimumCartTotal(String amount);

  /// No description provided for @cannotDeleteSellerInfo.
  ///
  /// In tr, this message translates to:
  /// **'Silinemez'**
  String get cannotDeleteSellerInfo;

  /// No description provided for @cannotDeleteSellerInfoWithProducts.
  ///
  /// In tr, this message translates to:
  /// **'Listelenen ürünleriniz varken satıcı bilgilerinizi güncelleyebilirsiniz.'**
  String get cannotDeleteSellerInfoWithProducts;

  /// No description provided for @sending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get sending;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
