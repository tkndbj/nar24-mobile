import 'package:flutter/material.dart';
import '../generated/l10n/app_localizations.dart'; // Import for localization
import 'package:go_router/go_router.dart'; // Import for navigation

class MarketBubbles extends StatelessWidget {
  final List<Map<String, dynamic>> bubbles;
  final Function(int) onNavItemTapped; // Callback for navigation

  MarketBubbles({super.key, required this.onNavItemTapped})
      : bubbles = [
          {
            'label': (BuildContext context) =>
                AppLocalizations.of(context).shops,
            'image': 'assets/images/shopbubble.png',
            'borderColor': Colors.orange,
            'backgroundColor': Colors.orange.withOpacity(0.2),
            'showComingSoon': false,
          },
          {
            'label': (BuildContext context) => 'Vitrin',
            'image': 'assets/images/vitrinbubble.png',
            'borderColor': Colors.green,
            'backgroundColor': Colors.green.withOpacity(0.2),
            'showComingSoon': false,
          },
          {
            'label': (BuildContext context) =>
                AppLocalizations.of(context).food,
            'image': 'assets/images/foodbubble.png',
            'borderColor': Colors.blue,
            'backgroundColor': Colors.blue.withOpacity(0.2),
            'showComingSoon': true,
          },
          {
            'label': (BuildContext context) => 'Market',
            'image': 'assets/images/marketbubble.png',
            'borderColor': Colors.pink,
            'backgroundColor': Colors.pink.withOpacity(0.2),
            'showComingSoon': true,
          },
        ];

  @override
  Widget build(BuildContext context) {
    // Determine if dark mode is active
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: bubbles.asMap().entries.map((entry) {
        final index = entry.key;
        final bubble = entry.value;
        return GestureDetector(
          onTap: () {
            if (index == 0) {
              context.push("/shop"); // Navigate to /shop for Shops bubble
            } else if (index == 1) {
              onNavItemTapped(4); // Use the callback for Vitrin bubble
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: bubble['borderColor'], width: 2),
                      color: bubble['backgroundColor'],
                    ),
                    child: Center(
                      child: Image.asset(
                        bubble['image'],
                        width: 50,
                        height: 50,
                      ),
                    ),
                  ),
                  if (bubble['showComingSoon'])
                    Positioned(
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: bubble['borderColor'],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          AppLocalizations.of(context).comingSoon,
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
              const SizedBox(height: 8),
              Text(
                bubble['label'](context),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
