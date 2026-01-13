import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';

class AskSellerBubble extends StatelessWidget {
  /// Called when the user taps the bubble.
  final VoidCallback onTap;

  /// Where to float the bubble. Defaults to bottom right.
  final Alignment alignment;

  /// Diameter of the circular bubble.
  final double size;

  /// Color of the circle border, image, and text background.
  final Color color;

  const AskSellerBubble({
    Key? key,
    required this.onTap,
    this.alignment = Alignment.bottomRight,
    this.size = 64,
    this.color = Colors.blue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bubbleBg =
        color.withOpacity(0.9); // Increased opacity for more solid color
    return Align(
      alignment: alignment,
      child: Padding(
        // Only horizontal padding + a tiny bottom margin
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bubbleBg,
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/asktoseller.png',
                    width: size * 0.5,
                    height: size * 0.5,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    AppLocalizations.of(context).askToSeller,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
