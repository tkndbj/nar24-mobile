import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';

class ProductPaymentSuccessScreen extends StatelessWidget {
  final Product? product;
  final String? productId;
  final String? orderId;

  const ProductPaymentSuccessScreen({
    Key? key,
    this.product,
    this.productId,
    this.orderId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset(
                  'assets/images/success.gif',
                  width: 170,
                  height: 170,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 80, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.paymentSuccessful,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.thankYouForYourPurchase,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 18),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 16,
                      color: isDark ? Colors.green[400] : Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.orderProcessedSuccessfully,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                ]),
                if (orderId != null && orderId!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    orderId!
                        .substring(0, orderId!.length.clamp(0, 8))
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.go("/"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      l10n.goToMarket,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      context.go('/receipts', extra: {'preventPop': true}),
                  child: Text(
                    l10n.goToPaymentDetails,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
