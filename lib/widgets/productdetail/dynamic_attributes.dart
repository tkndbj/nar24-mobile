// File: dynamic_attributes_widget.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/product_detail_provider.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../models/product.dart';

class DynamicAttributesWidget extends StatefulWidget {
  const DynamicAttributesWidget({Key? key}) : super(key: key);

  @override
  _DynamicAttributesWidgetState createState() =>
      _DynamicAttributesWidgetState();
}

class _DynamicAttributesWidgetState extends State<DynamicAttributesWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<ProductDetailProvider>(context, listen: false);
    final product = provider.product;
    final l10n = AppLocalizations.of(context);

    if (product == null) return const SizedBox.shrink();
    final displayAttributes = _buildDisplayAttributes(product);
    if (displayAttributes.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg =
        isDark ? const Color.fromARGB(255, 40, 38, 59) : Colors.white;
    final attributeBg = isDark
        ? const Color(0xFF1C1A29)
        : const Color.fromARGB(255, 243, 243, 243);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: containerBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l10n.productDetails ?? 'Product Details',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Attributes Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
            child: _buildAttributesGrid(displayAttributes, attributeBg, l10n),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _buildDisplayAttributes(Product product) {
    final Map<String, dynamic> combined = {};

    // Top-level spec fields first
    if (product.gender?.isNotEmpty == true) combined['gender'] = product.gender;
    if (product.productType?.isNotEmpty == true)
      combined['productType'] = product.productType;
    if (product.clothingSizes?.isNotEmpty == true)
      combined['clothingSizes'] = product.clothingSizes;
    if (product.clothingFit?.isNotEmpty == true)
      combined['clothingFit'] = product.clothingFit;
    if (product.clothingTypes?.isNotEmpty == true)
      combined['clothingTypes'] = product.clothingTypes;
    if (product.pantSizes?.isNotEmpty == true)
      combined['pantSizes'] = product.pantSizes;
    if (product.pantFabricTypes?.isNotEmpty == true)
      combined['pantFabricTypes'] = product.pantFabricTypes;
    if (product.footwearSizes?.isNotEmpty == true)
      combined['footwearSizes'] = product.footwearSizes;
    if (product.jewelryMaterials?.isNotEmpty == true)
      combined['jewelryMaterials'] = product.jewelryMaterials;
    if (product.consoleBrand?.isNotEmpty == true)
      combined['consoleBrand'] = product.consoleBrand;
    if (product.curtainMaxWidth != null)
      combined['curtainMaxWidth'] = product.curtainMaxWidth;
    if (product.curtainMaxHeight != null)
      combined['curtainMaxHeight'] = product.curtainMaxHeight;

    // Remaining misc attributes map (backward compat for old products)
    product.attributes.forEach((key, value) {
      if (!combined.containsKey(key)) combined[key] = value;
    });

    return combined;
  }

  Widget _buildAttributesGrid(Map<String, dynamic> attributes,
      Color attributeBg, AppLocalizations l10n) {
    // Filter out null/empty values and format attributes using the utility
    final formattedAttributes = <String, String>{};

    attributes.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        try {
          // Use the utility to get localized title and value
          final localizedTitle =
              AttributeLocalizationUtils.getLocalizedAttributeTitle(key, l10n);
          final localizedValue =
              AttributeLocalizationUtils.getLocalizedAttributeValue(
                  key, value, l10n);

          if (localizedValue.isNotEmpty) {
            formattedAttributes[localizedTitle] = localizedValue;
          }
        } catch (e) {
          print('Error localizing attribute $key: $e');
          // Simple fallback - just use the key and value as-is
          formattedAttributes[key] = value.toString();
        }
      }
    });

    if (formattedAttributes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: formattedAttributes.entries.map((entry) {
        return _buildAttributeCard(entry.key, entry.value, attributeBg);
      }).toList(),
    );
  }

  Widget _buildAttributeCard(
      String title, String value, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(
          color: Colors.orange,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
