import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart'; // Adjust path as needed
import '../../constants/all_in_one_category_data.dart'; // Import category data

class BestSellerLabel extends StatelessWidget {
  final int rank;
  final String category; // Parent category
  final String subcategory;

  const BestSellerLabel({
    Key? key,
    required this.rank,
    required this.category,
    required this.subcategory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Get localized subcategory name
    final localizedSubcategory = AllInOneCategoryData.localizeSubcategoryKey(
      category,
      subcategory,
      l10n,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.purple, Colors.pink],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        l10n.bestSellerLabel(rank, localizedSubcategory),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}