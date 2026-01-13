// lib/widgets/language_selector.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../generated/l10n/app_localizations.dart';
import '../main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LanguageSelector extends StatelessWidget {
  final Color? iconColor;
  final double iconSize;
  final bool updateFirestore;

  const LanguageSelector({
    super.key,
    this.iconColor,
    this.iconSize = 24,
    this.updateFirestore = true,
  });

  /// Updates the user's language preference in Firestore.
  static Future<void> _updateFirestoreLanguage(String languageCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final currentLangCode = userDoc.data()?['languageCode'];

      if (currentLangCode != languageCode) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'languageCode': languageCode});

        debugPrint('Language preference updated to: $languageCode');
      }
    } catch (e) {
      debugPrint('Error updating language preference: $e');
    }
  }

  /// Shows the language selector modal and handles the result.
  ///
  /// Idiomatic pattern: Modal returns selected value, side effects happen after close.
  Future<void> _showLanguageSelector(BuildContext context) async {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final currentLanguageCode = localeProvider.locale.languageCode;

    // Show modal and await the selected language code (or null if dismissed)
    final selectedLanguageCode = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => _LanguageOptionsSheet(
        currentLanguageCode: currentLanguageCode,
      ),
    );

    // Handle selection after modal is fully closed - no race conditions possible
    if (selectedLanguageCode != null && selectedLanguageCode != currentLanguageCode) {
      // Update locale
      localeProvider.setLocale(Locale(selectedLanguageCode));

      // Update Firestore (fire-and-forget with proper handling)
      if (updateFirestore) {
        _updateFirestoreLanguage(selectedLanguageCode).ignore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showLanguageSelector(context),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.language,
            color: iconColor ?? Theme.of(context).textTheme.bodyMedium?.color,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

/// Separate widget for the modal content.
/// Returns the selected language code via Navigator.pop().
class _LanguageOptionsSheet extends StatelessWidget {
  final String currentLanguageCode;

  const _LanguageOptionsSheet({
    required this.currentLanguageCode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.settingsLanguage,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Language options
          _LanguageOptionTile(
            languageCode: 'en',
            languageName: l10n.english,
            flag: '🇬🇧',
            isSelected: currentLanguageCode == 'en',
          ),
          _LanguageOptionTile(
            languageCode: 'tr',
            languageName: l10n.turkish,
            flag: '🇹🇷',
            isSelected: currentLanguageCode == 'tr',
          ),
          _LanguageOptionTile(
            languageCode: 'ru',
            languageName: l10n.russian,
            flag: '🇷🇺',
            isSelected: currentLanguageCode == 'ru',
          ),
          SafeArea(
            top: false,
            child: const SizedBox(height: 16),
          ),
        ],
      ),
    );
  }
}

/// Individual language option tile.
/// Simply pops with the language code - no side effects.
class _LanguageOptionTile extends StatelessWidget {
  final String languageCode;
  final String languageName;
  final String flag;
  final bool isSelected;

  const _LanguageOptionTile({
    required this.languageCode,
    required this.languageName,
    required this.flag,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFF00A86B);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? selectedColor.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // Simply return the selected language code - caller handles side effects
          onTap: () => Navigator.pop(context, languageCode),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? selectedColor : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    languageName,
                    style: GoogleFonts.inter(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? selectedColor : null,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: selectedColor,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
