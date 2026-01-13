// lib/widgets/icon_with_badge.dart

import 'package:flutter/material.dart';

class IconWithBadge extends StatelessWidget {
  final IconData iconData;
  final int badgeCount;
  final String label;

  const IconWithBadge({
    Key? key,
    required this.iconData,
    required this.badgeCount,
    required this.label,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Jade green color
    const Color jadeGreen = Color(0xFF00A86B);

    return Semantics(
      label: label,
      hint: badgeCount > 0
          ? '$badgeCount new notifications'
          : 'No new notifications',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Icon
          Icon(
            iconData,
            size: 24.0,
            // No specific color here, so it respects parent IconTheme color
          ),

          // Badge
          if (badgeCount > 0)
            Positioned(
              right: -6,
              top: -3,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: const BoxDecoration(
                  color: jadeGreen,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Center(
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontFamily: 'Figtree',
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
