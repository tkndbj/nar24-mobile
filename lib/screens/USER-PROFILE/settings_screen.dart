import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart'; // Import localization
import 'package:provider/provider.dart'; // Import provider for theme management
import '../../theme_provider.dart'; // Import ThemeProvider
import '../../widgets/language_selector.dart'; // Import the LanguageSelector widget

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Access localized strings
    final l10n = AppLocalizations.of(context);

    // Access ThemeProvider
    final themeProvider = Provider.of<ThemeProvider>(context);

    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Set container background based on dark mode
    final containerBackground = isDarkMode
        ? const Color.fromARGB(255, 39, 36, 57)
        : theme.colorScheme.surface;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor, // Use theme color
        elevation: theme.appBarTheme.elevation,
        title: Text(
          l10n.settingsTitle,
          style: theme.appBarTheme.titleTextStyle,
        ),
        iconTheme: theme.appBarTheme.iconTheme, // Back button color
      ),
      backgroundColor: theme.scaffoldBackgroundColor, // Use theme color
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          color: containerBackground,
          elevation: 8,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Language Section
                Text(
                  l10n.settingsSectionLanguage, // e.g., "Language"
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                // Language Selector Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Language Label
                    Text(
                      l10n.settingsLanguage, // e.g., "Select Language"
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    // Language Selector Widget with icon color black in light mode
                    LanguageSelector(
                      iconColor: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                // Theme Switch Section
                Text(
                  l10n.settingsTheme, // e.g., "Theme"
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.darkMode, // e.g., "Dark Mode"
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (value) {
                        themeProvider.toggleThemeWithPersistence(value);
                      },
                      activeThumbColor: theme.colorScheme.secondary, // Theme color
                    ),
                  ],
                ),
                // Additional settings can be added here.
              ],
            ),
          ),
        ),
      ),
    );
  }
}
