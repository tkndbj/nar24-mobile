import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';

class DeliveryOptionsAccordion extends StatelessWidget {
  final String? selectedDeliveryOption;
  final ValueChanged<String?> onDeliveryOptionChanged;

  const DeliveryOptionsAccordion({
    Key? key,
    required this.selectedDeliveryOption,
    required this.onDeliveryOptionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            l10n.deliveryOptions,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color.fromARGB(255, 33, 31, 49)
                : Colors.white,
            borderRadius: BorderRadius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildDeliveryRadio(l10n.selfDelivery, 'Self Delivery'),
                const SizedBox(width: 16),
                _buildDeliveryRadio(l10n.nar24Delivery, 'Fast Delivery'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryRadio(String label, String value) {
    return Row(
      children: [
        Radio<String>(
          value: value,
          groupValue: selectedDeliveryOption,
          onChanged: onDeliveryOptionChanged,
          activeColor: const Color(0xFF00A86B),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}
