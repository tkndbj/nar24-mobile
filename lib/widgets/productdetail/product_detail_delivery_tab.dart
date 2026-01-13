// lib/widgets/productdetail/product_detail_delivery_tab.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/product_detail_provider.dart';

class ProductDetailDeliveryTab extends StatelessWidget {
  const ProductDetailDeliveryTab({Key? key}) : super(key: key);

  void _showDeliveryModal(BuildContext context, String deliveryOption) {
    final l10n = AppLocalizations.of(context);

    String title;
    String description;

    if (deliveryOption == 'Fast Delivery') {
      title = l10n.fastDeliveryTitle;
      description = l10n.fastDeliveryDescription;
    } else if (deliveryOption == 'Self Delivery') {
      title = l10n.selfDeliveryTitle;
      description = l10n.selfDeliveryDescription;
    } else {
      // Handle unknown delivery options if necessary
      title = l10n.unknownDeliveryTitle;
      description = l10n.unknownDeliveryDescription;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color.fromARGB(255, 39, 36, 57),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: MediaQuery.of(context).viewInsets, // To handle keyboard
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Indicator
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProductDetailProvider>(context);
    final product = provider.product;
    final l10n = AppLocalizations.of(context);

    if (product == null) {
      return const SizedBox.shrink();
    }

    String deliveryOption = product.deliveryOption;
    String deliveryText;
    if (deliveryOption == 'Self Delivery') {
      deliveryText = l10n.selfDeliveryText;
    } else if (deliveryOption == 'Fast Delivery') {
      deliveryText = l10n.fastDeliveryText;
    } else {
      deliveryText = l10n.unknownDeliveryText; // Handle unknown options
    }

    return Semantics(
      button: true,
      label: deliveryOption == 'Self Delivery'
          ? l10n.selfDeliverySectionTapHint
          : deliveryOption == 'Fast Delivery'
              ? l10n.fastDeliverySectionTapHint
              : l10n.unknownDeliverySectionTapHint,
      child: GestureDetector(
        onTap: () => _showDeliveryModal(context, deliveryOption),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Row with Arrow Icon
              Row(
                children: [
                  // Icon and Title aligned to the left
                  Expanded(
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/delivery2.png',
                          width: 24, // Reduced width
                          height: 24, // Reduced height
                          fit: BoxFit.contain,
                          semanticLabel: l10n.deliveryIconLabel,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          deliveryOption,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).brightness == Brightness.light
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ">" Icon aligned to the right
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Delivery Text with dynamic color from theme
              Text(
                deliveryText,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
