// lib/widgets/stats/stat_card.dart

import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const StatCard({
    Key? key,
    required this.title,
    required this.value,
    this.valueColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use bodyMedium or another appropriate text style
    final defaultTextColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300), // Thin gray border
        borderRadius: BorderRadius.circular(8), // Smooth corners
      ),
      color: Colors.white, // White background for better contrast
      elevation: 2, // Slight elevation for depth
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                  fontSize: 16,
                  color: defaultTextColor,
                )),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: valueColor ?? defaultTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
