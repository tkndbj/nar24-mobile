// lib/widgets/productdetail/product_detail_tracker.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/product_detail_provider.dart';

class ProductDetailTracker extends StatelessWidget {
  const ProductDetailTracker({Key? key}) : super(key: key);

  Widget _buildTrackerItem({
    required BuildContext context,
    required IconData icon,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5), // Transparent black background
        borderRadius: BorderRadius.circular(8), // Smooth rounded corners
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductDetailProvider>(
      builder: (context, provider, child) {
        final product = provider.product;
        if (product == null) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sold (purchase count) tracker
            _buildTrackerItem(
              context: context,
              icon: Icons.shopping_bag,
              count: product.purchaseCount,
            ),
            // View (click count) tracker
            _buildTrackerItem(
              context: context,
              icon: Icons.remove_red_eye,
              count: product.clickCount,
            ),
            // Cart tracker
            _buildTrackerItem(
              context: context,
              icon: Icons.add_shopping_cart,
              count: product.cartCount,
            ),
            // Favorites tracker
            _buildTrackerItem(
              context: context,
              icon: Icons.favorite,
              count: product.favoritesCount,
            ),
          ],
        );
      },
    );
  }
}
