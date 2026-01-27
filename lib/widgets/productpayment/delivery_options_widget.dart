import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/product_payment_provider.dart';

class DeliveryOptionsWidget extends StatelessWidget {
  const DeliveryOptionsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<ProductPaymentProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingDeliverySettings) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                l10n.deliveryOptions,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _DeliveryCard(
                    title: l10n.deliveryOption3,
                    description: l10n.deliveryText3,
                    value: 'normal',
                    selectedValue: provider.selectedDeliveryOption,
                    onChanged: (value) => provider.setDeliveryOption(value),
                    isDark: isDark,
                    price: provider.cartCalculatedTotal >=
                            provider.normalFreeThreshold
                        ? l10n.free
                        : '${provider.normalPrice.toStringAsFixed(0)} TL',
                  ),
                  const SizedBox(width: 12),
                  _DeliveryCard(
                    title: l10n.deliveryOption2,
                    description: l10n.deliveryText2,
                    value: 'express',
                    selectedValue: provider.selectedDeliveryOption,
                    onChanged: (value) => provider.setDeliveryOption(value),
                    isDark: isDark,
                    price: provider.cartCalculatedTotal >=
                            provider.expressFreeThreshold
                        ? l10n.free
                        : '${provider.expressPrice.toStringAsFixed(0)} TL',
                    isDisabled: !provider.isExpressAvailable, // ADD
                    disabledReason: l10n.expressDisabledWithBenefit, // ADD
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final String title;
  final String description;
  final String value;
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final bool isDark;
  final String price;
  final bool isDisabled; // ADD
  final String? disabledReason;

  const _DeliveryCard({
    Key? key,
    required this.title,
    required this.description,
    required this.value,
    required this.selectedValue,
    required this.onChanged,
    required this.isDark,
    required this.price,
    this.isDisabled = false, // ADD
    this.disabledReason,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedValue == value;

    return GestureDetector(
      onTap: isDisabled ? null : () => onChanged(value), // MODIFY
      child: Opacity(
        // ADD wrapper
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: isDisabled ? 190 : 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDisabled
                  ? Colors.grey.withOpacity(0.3) // ADD
                  : (isSelected ? Colors.orange : Colors.grey.withOpacity(0.3)),
              width: isSelected && !isDisabled ? 2 : 1, // MODIFY
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Radio<String>(
                    value: value,
                    groupValue: selectedValue,
                    onChanged: isDisabled ? null : onChanged, // MODIFY
                    activeColor: Colors.orange,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            isDisabled ? Colors.grey : Colors.orange, // MODIFY
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  isDisabled && disabledReason != null // ADD conditional
                      ? disabledReason!
                      : description,
                  style: TextStyle(
                    fontSize: isDisabled ? 10 : 12,
                    color: isDisabled
                        ? Colors.orange.shade700 // ADD
                        : (isDark ? Colors.white : Colors.black),
                    fontStyle:
                        isDisabled ? FontStyle.italic : FontStyle.normal, // ADD
                  ),
                  maxLines: isDisabled ? 5 : 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isDisabled) ...[
                const SizedBox(height: 4),
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
