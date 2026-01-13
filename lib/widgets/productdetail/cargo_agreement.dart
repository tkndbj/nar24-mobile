// lib/widgets/productdetail/cargo_agreement.dart

import 'package:flutter/material.dart';

class CargoAgreement extends StatelessWidget {
  /// These properties are set via the admin panel (per-user).
  final String agreementText;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign textAlign;
  final Color textColor;
  final Color gradientColor1;
  final Color gradientColor2;

  const CargoAgreement({
    Key? key,
    this.agreementText = "",
    this.fontSize = 16.0,
    this.fontWeight = FontWeight.normal,
    this.textAlign = TextAlign.left,
    this.textColor = Colors.white,
    this.gradientColor1 = const Color(0xFFB0BEC5), // Default greyish
    this.gradientColor2 = const Color(0xFF607D8B), // Default blue-grey
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If there's no agreement text (or only whitespace), return an empty widget.
    if (agreementText.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientColor1, gradientColor2],
        ),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Text(
        agreementText,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: textColor,
        ),
      ),
    );
  }
}
