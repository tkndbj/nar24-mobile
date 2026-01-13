// lib/widgets/productpayment/product_cards_grid.dart

import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/product.dart';
import '../product_card.dart';

class ProductCardsGrid extends StatelessWidget {
  final List<Product> products;
  final String? selectedColor; // Kept for compatibility, but optional

  const ProductCardsGrid({
    Key? key,
    required this.products,
    this.selectedColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Retrieve localized strings.
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Horizontally scrollable row of product cards.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: products.map((product) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SizedBox(
                  width: 200, // Fixed width to constrain the card
                  child: ProductCard(
                    product: product,
                    showCartIcon: false,
                    selectedColor: selectedColor,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16.0),
        // Total Price display with a light gray background spanning full width.
        _TotalPriceWidget(products: products, l10n: l10n),
      ],
    );
  }
}

class _TotalPriceWidget extends StatelessWidget {
  final List<Product> products;
  final AppLocalizations l10n;

  const _TotalPriceWidget({
    Key? key,
    required this.products,
    required this.l10n,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double totalPrice = products.fold(
      0.0,
      (previousValue, product) => previousValue + (product.price ?? 0.0),
    );
    final String currency =
        products.isNotEmpty ? products.first.currency : "TL";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          GradientText(
            text: '${totalPrice.toStringAsFixed(0)} $currency',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.pink],
            ),
          ),
        ],
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;

  const GradientText({
    Key? key,
    required this.text,
    required this.style,
    required this.gradient,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        style: style,
      ),
    );
  }
}
