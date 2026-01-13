// lib/widgets/icon_with_badge.dart

import 'package:flutter/material.dart';

class IconWithBadge extends StatelessWidget {
  final IconData iconData;
  final int badgeCount;
  final Color color; // Property for icon color
  final String? label; // Optional label for semantics
  final Color badgeColor; // Optional badge color

  const IconWithBadge({
    Key? key,
    required this.iconData,
    required this.badgeCount,
    required this.color,
    this.label,
    this.badgeColor = const Color(0xFF00A86B), // Default badge color
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          iconData,
          size: 24.0,
          color: color,
        ),
        if (badgeCount > 0)
          Positioned(
            right: -6,
            top: -3, // Adjust position as needed
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: badgeColor, // Badge background color
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
              child: Center(
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white, // Badge text color
                    fontSize: 8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
