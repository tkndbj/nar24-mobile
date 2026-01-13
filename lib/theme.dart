// lib/theme.dart

import 'package:flutter/material.dart';

// Define a ThemeExtension to hold custom colors
class CustomColors extends ThemeExtension<CustomColors> {
  final Color? iconAccentColor;
  final Color? priceColor;
  final Color? sidebarBorderColor; // For sidebar right border
  final Color?
      bottomNavBarBorderColor; // Not used directly but kept for extensibility
  final Color? featuredLabelColor; // For "Featured" label
  final Color? badgeColor; // For badges (notifications/inbox)
  final Color? jadeColor; // Added jade color
  final Color? propertyCardBackground; // Background for property cards
  // NEW: Add separate backgrounds for product and car cards
  final Color? productCardBackground;
  final Color? carCardBackground;
  final Color? purpleColor;
  CustomColors({
    this.iconAccentColor,
    this.priceColor,
    this.sidebarBorderColor,
    this.bottomNavBarBorderColor,
    this.featuredLabelColor,
    this.badgeColor,
    this.jadeColor, // Initialize jade color
    this.propertyCardBackground, // Initialize PropertyCard background color
    this.productCardBackground,
    this.carCardBackground,
    this.purpleColor,
  });

  @override
  CustomColors copyWith({
    Color? iconAccentColor,
    Color? priceColor,
    Color? sidebarBorderColor,
    Color? bottomNavBarBorderColor,
    Color? featuredLabelColor,
    Color? badgeColor,
    Color? jadeColor, // Copy jade color
    Color? propertyCardBackground, // Copy propertyCardBackground
    Color? productCardBackground,
    Color? carCardBackground,
    Color? purpleColor,
  }) {
    return CustomColors(
      iconAccentColor: iconAccentColor ?? this.iconAccentColor,
      priceColor: priceColor ?? this.priceColor,
      sidebarBorderColor: sidebarBorderColor ?? this.sidebarBorderColor,
      bottomNavBarBorderColor:
          bottomNavBarBorderColor ?? this.bottomNavBarBorderColor,
      featuredLabelColor: featuredLabelColor ?? this.featuredLabelColor,
      badgeColor: badgeColor ?? this.badgeColor,
      jadeColor: jadeColor ?? this.jadeColor, // Copy jade color
      propertyCardBackground:
          propertyCardBackground ?? this.propertyCardBackground,
      productCardBackground:
          productCardBackground ?? this.productCardBackground,
      carCardBackground: carCardBackground ?? this.carCardBackground,
      purpleColor: purpleColor ?? this.purpleColor,
    );
  }

  @override
  CustomColors lerp(ThemeExtension<CustomColors>? other, double t) {
    if (other is! CustomColors) return this;
    return CustomColors(
      iconAccentColor: Color.lerp(iconAccentColor, other.iconAccentColor, t),
      priceColor: Color.lerp(priceColor, other.priceColor, t),
      sidebarBorderColor:
          Color.lerp(sidebarBorderColor, other.sidebarBorderColor, t),
      bottomNavBarBorderColor:
          Color.lerp(bottomNavBarBorderColor, other.bottomNavBarBorderColor, t),
      featuredLabelColor:
          Color.lerp(featuredLabelColor, other.featuredLabelColor, t),
      badgeColor: Color.lerp(badgeColor, other.badgeColor, t),
      jadeColor: Color.lerp(jadeColor, other.jadeColor, t), // Lerp jade
      purpleColor: Color.lerp(purpleColor, other.purpleColor, t),
      propertyCardBackground:
          Color.lerp(propertyCardBackground, other.propertyCardBackground, t),
      productCardBackground:
          Color.lerp(productCardBackground, other.productCardBackground, t),
      carCardBackground:
          Color.lerp(carCardBackground, other.carCardBackground, t),
    );
  }
}

class AppThemes {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor:
        const Color.fromARGB(255, 255, 255, 255), // Sand color as primary
    scaffoldBackgroundColor: Colors.white,
    colorScheme: const ColorScheme.light(
      primary: Color.fromARGB(255, 32, 32, 32),
      secondary: Color.fromARGB(255, 255, 255, 255), // Jade green for buttons
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.black,
      // background/onBackground removed in your original code
    ),
    // appBarTheme
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      iconTheme: IconThemeData(color: Colors.black),
      titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Figtree'),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFC8C8C8),
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.black,
      selectedLabelStyle: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
      ),
      // Border is handled in the screen code by using colorScheme.secondary
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
        color: Color.fromARGB(255, 29, 29, 0), // Olive Green for general text
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
      bodySmall: TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
    ),
    buttonTheme: const ButtonThemeData(
      buttonColor: Color(0xFF00A86B), // Sand color
      textTheme: ButtonTextTheme.primary,
    ),
    extensions: <ThemeExtension<dynamic>>[
      CustomColors(
        iconAccentColor: const Color.fromARGB(255, 255, 127, 80), // Coral
        priceColor: const Color(0xFF814141),
        sidebarBorderColor: Colors.black,
        bottomNavBarBorderColor: Colors.transparent,
        featuredLabelColor: Colors.orange,
        badgeColor: Colors.red,
        jadeColor: const Color(0xFF00A86B),
        purpleColor: const Color(0xFF5D3FD3),
        propertyCardBackground: Colors.white,
        // NEW: Provide product and car card backgrounds (slightly different, if desired)
        productCardBackground: Colors.white,
        carCardBackground: Color(0xFFF2F2F2), // Example slightly off-white
      ),
    ],
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    // A dark purple, gray combination for overall background
    scaffoldBackgroundColor: const Color(0xFF1C1A29),
    primaryColor: const Color(0xFF1C1A29),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF1C1A29),
      secondary: Color(0xFF00A86B),
      // Slightly lighter or different for cards if you wish, but we'll override with extension below
      surface: Color(0xFF2A2A2A),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Color.fromARGB(255, 35, 33, 51),
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Figtree'),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1C1A29),
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white70,
      selectedLabelStyle: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'Figtree',
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: const TextTheme(
        bodyLarge: TextStyle(
          fontFamily: 'Figtree',
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Figtree',
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodySmall: TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        )),
    buttonTheme: const ButtonThemeData(
      buttonColor: Color(0xFF00A86B), // Jade green
      textTheme: ButtonTextTheme.primary,
    ),
    extensions: <ThemeExtension<dynamic>>[
      CustomColors(
        iconAccentColor: Colors.orange,
        priceColor: Colors.blue, // or keep your previous color
        sidebarBorderColor: null,
        bottomNavBarBorderColor: Colors.transparent,
        featuredLabelColor: Colors.orange,
        badgeColor: Colors.red,
        jadeColor: Color(0xFF00A86B),
        purpleColor: const Color(0xFF5D3FD3),
        // Slightly different dark purple/gray backgrounds for each card type:
        propertyCardBackground: Color.fromARGB(255, 37, 35, 54),
        productCardBackground: Color.fromARGB(255, 33, 31, 49),
        carCardBackground: Color.fromARGB(255, 33, 31, 49),
      ),
    ],
  );
}
