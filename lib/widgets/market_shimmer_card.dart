import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Lightweight shimmer placeholder for market_screen category filter products
/// Matches the 160px width cards used in horizontal scrolling lists
class MarketShimmerCard extends StatelessWidget {
  const MarketShimmerCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Dark mode colors matching theme Color(0xFF1C1A29)
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 30, 28, 44)
        : Colors.grey[300]!;
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 33, 31, 49)
        : Colors.grey[100]!;

    return SizedBox(
      width: 160,
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        period: const Duration(milliseconds: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image placeholder (square aspect ratio to match ProductCard)
            AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Title placeholder (2 lines)
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 12,
              width: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),

            // Rating placeholder
            Container(
              height: 10,
              width: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),

            // Price placeholder
            Container(
              height: 14,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
