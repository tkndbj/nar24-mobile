// lib/widgets/shop_horizontal_list_widget.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../providers/shop_widget_provider.dart';
import 'shop/shop_card_widget.dart';
import '../generated/l10n/app_localizations.dart';

class ShopHorizontalListWidget extends StatelessWidget {
  const ShopHorizontalListWidget({Key? key}) : super(key: key);

  // Determine if current device is a tablet
  bool _isTablet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final orientation = mediaQuery.orientation;

    // Consider it a tablet if shortest side is >= 600dp
    final shortestSide =
        orientation == Orientation.portrait ? screenWidth : screenHeight;
    return shortestSide >= 600 ||
        (orientation == Orientation.landscape && screenWidth >= 900);
  }

  // Calculate responsive dimensions
  Map<String, double> _getResponsiveDimensions(BuildContext context) {
    final isTablet = _isTablet(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (!isTablet) {
      // Mobile dimensions (unchanged)
      return {
        'containerHeight': 260.0,
        'cardWidth': 180.0,
        'cardSpacing': 12.0,
        'horizontalPadding': 8.0,
        'titleFontSize': 20.0,
      };
    }

    // Tablet dimensions - scale based on screen width
    final double cardWidth = screenWidth > 1200 ? 240.0 : 220.0;
    final double containerHeight = screenWidth > 1200 ? 320.0 : 300.0;

    return {
      'containerHeight': containerHeight,
      'cardWidth': cardWidth,
      'cardSpacing': 16.0,
      'horizontalPadding': 12.0,
      'titleFontSize': 22.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode
        ? const Color.fromARGB(255, 40, 37, 58) // dark base
        : Colors.grey.shade300; // light base
    final highlightColor = isDarkMode
        ? const Color.fromARGB(255, 60, 57, 78) // slightly lighter dark
        : Colors.grey.shade100;

    final dimensions = _getResponsiveDimensions(context);
    final isTablet = _isTablet(context);

    return Consumer<ShopWidgetProvider>(
      builder: (context, widgetProv, _) {
        final theme = Theme.of(context);
        final textColor =
            theme.brightness == Brightness.dark ? Colors.white : Colors.black;

        // Loading state with shimmer
        if (widgetProv.isLoadingMore && widgetProv.shops.isEmpty) {
          return SizedBox(
            height: dimensions['containerHeight']!,
            child: Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                    horizontal: dimensions['horizontalPadding']!),
                itemCount: 5, // show 5 placeholder shop cards
                separatorBuilder: (_, __) =>
                    SizedBox(width: dimensions['cardSpacing']!),
                itemBuilder: (context, index) => Container(
                  width: dimensions['cardWidth']!,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          );
        }

        // No shops state
        if (widgetProv.shops.isEmpty) {
          return SizedBox(
            height: isTablet ? 280.0 : 240.0, // Slightly taller on tablets
            child: Center(
              child: Text(
                l10n.featuredShops,
                style: TextStyle(
                  color: textColor,
                  fontSize: isTablet ? 18.0 : 16.0,
                ),
              ),
            ),
          );
        }

        // The horizontal carousel
        return SizedBox(
          height: dimensions['containerHeight']!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  dimensions['horizontalPadding']!,
                  isTablet ? 20.0 : 16.0, // More top padding on tablets
                  16.0,
                  isTablet ? 12.0 : 8.0, // More bottom padding on tablets
                ),
                child: Text(
                  l10n.featuredShops,
                  style: TextStyle(
                    fontSize: dimensions['titleFontSize']!,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                      horizontal: dimensions['horizontalPadding']!),
                  itemCount: widgetProv.shops.length,
                  itemBuilder: (context, index) {
                    final doc = widgetProv.shops[index];
                    final data = doc.data()! as Map<String, dynamic>;
                    final avg =
                        (data['averageRating'] as num?)?.toDouble() ?? 0.0;

                    return Container(
                      width: dimensions['cardWidth']!,
                      margin: EdgeInsets.only(
                        right: index < widgetProv.shops.length - 1
                            ? dimensions['cardSpacing']!
                            : 0,
                      ),
                      child: ShopCardWidget(
                        shop: data,
                        shopId: doc.id,
                        averageRating: avg,
                        // Pass tablet flag to ShopCardWidget if it supports it
                        // Otherwise, the card will adapt to the container size
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
