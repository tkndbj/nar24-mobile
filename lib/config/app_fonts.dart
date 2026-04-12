// lib/config/app_fonts.dart
//
// Single source of truth for the app's primary font family.
//
// To swap the entire app's font, change the value of [primary] below to one
// of the constants declared in this file. The new family must be declared in
// pubspec.yaml under `flutter > fonts` with the same name.

class AppFonts {
  AppFonts._();

  // ↓↓↓ CHANGE THIS ONE LINE TO SWAP FONTS APP-WIDE ↓↓↓
  static const String primary = googleSans;

  // Available bundled font families. Names must match `family:` entries in
  // pubspec.yaml exactly.
  static const String figtree = 'Figtree';
  static const String googleSans = 'GoogleSans';
}
