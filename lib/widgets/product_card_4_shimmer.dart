import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ProductCard4Shimmer extends StatelessWidget {
  const ProductCard4Shimmer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Dark mode colors
    final baseColor = isDarkMode 
        ? const Color.fromARGB(255, 35, 33, 50) 
        : Colors.grey[300]!;
    final highlightColor = isDarkMode 
        ? const Color.fromARGB(255, 33, 31, 49) 
        : Colors.grey[100]!;

    const double imageHeight = 80.0;
    const double imageWidth = 90.0;
    const double borderRadius = 8.0;
    const double paddingAll = 4.0;
    const double spacingTiny = 1.0;
    const double spacingSmall = 2.0;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: imageHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image placeholder
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(borderRadius),
                bottomLeft: Radius.circular(borderRadius),
              ),
              child: Container(
                width: imageWidth,
                height: imageHeight,
                color: Colors.white,
              ),
            ),
            
            // Content placeholder
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(paddingAll),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Product name placeholder
                    Container(
                      width: double.infinity,
                      height: 14.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                    const SizedBox(height: spacingTiny),
                    
                    // Brand/model placeholder (shorter)
                    Container(
                      width: 100.0,
                      height: 14.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                    const SizedBox(height: spacingSmall),
                    
                    // Rating placeholder
                    Row(
                      children: [
                        Container(
                          width: 60.0,
                          height: 10.0,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                        const SizedBox(width: spacingSmall),
                        Container(
                          width: 20.0,
                          height: 10.0,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: spacingTiny),
                    
                    // Price placeholder
                    Container(
                      width: 80.0,
                      height: 12.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}