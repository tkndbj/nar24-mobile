import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../generated/l10n/app_localizations.dart';

/// Custom formatter that forces lowercase but capitalizes the first letter of each word (Title Case)
class _TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Convert all to lowercase first
    String text = newValue.text.toLowerCase();

    // Capitalize the first letter of each word
    text = text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    return TextEditingValue(
      text: text,
      selection: newValue.selection,
    );
  }
}

/// Custom formatter that forces lowercase but capitalizes the first letter only
class _FirstLetterCapitalFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Convert all to lowercase first
    String text = newValue.text.toLowerCase();

    // Capitalize the first letter
    text = text[0].toUpperCase() + text.substring(1);

    return TextEditingValue(
      text: text,
      selection: newValue.selection,
    );
  }
}

class ProductInfoForm extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;

  const ProductInfoForm({
    Key? key,
    required this.titleController,
    required this.descriptionController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.white,
            borderRadius: BorderRadius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              controller: titleController,
              maxLength: 100,
              textCapitalization: TextCapitalization.none,
              inputFormatters: [
                _TitleCaseFormatter(),
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.enterProductTitle,
                hintStyle: const TextStyle(
                  color: Colors.grey,
                ),
              ),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.pleaseEnterProductTitle;
                }
                return null;
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            l10n.detailedDescription,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.white,
            borderRadius: BorderRadius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              controller: descriptionController,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.none,
              inputFormatters: [
                _FirstLetterCapitalFormatter(),
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.enterDetailedDescription,
                hintStyle: const TextStyle(
                  color: Colors.grey,
                ),
              ),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.pleaseEnterDescription;
                }
                return null;
              },
            ),
          ),
        ),
      ],
    );
  }
}
