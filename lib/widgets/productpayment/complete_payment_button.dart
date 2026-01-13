import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_payment_provider.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class CompletePaymentButton extends StatelessWidget {
  const CompletePaymentButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Consumer<ProductPaymentProvider>(
      builder: (context, provider, _) {
        final isDisabled = provider.isProcessingPayment || !provider.hasAcceptedAgreement;

        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isDisabled
                ? null
                : () async {
                bool success = await provider.confirmPayment(context);
                if (success) {
                  // Since ProductPaymentSuccessScreen expects a single product,
                  // we'll use the first item for now.
                  final firstItem = provider.items.first;
                  context.go('/product_payment_success', extra: {
                    'product': firstItem['product'],
                    'productId': firstItem['product'].id,                    
                  });
                }
              },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              backgroundColor: const Color(0xFF00A86B),
              disabledBackgroundColor: Colors.grey[300],
              foregroundColor: Colors.white,
            ),
            child: provider.isProcessingPayment
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    l10n.confirmPayment,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
          ),
        );
      },
    );
  }
}
