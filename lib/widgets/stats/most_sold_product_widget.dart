// lib/widgets/stats/most_sold_product_widget.dart

import 'package:flutter/material.dart';
import '../../models/product.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class MostSoldProductWidget extends StatelessWidget {
  final Product product;
  final int soldQuantity;

  const MostSoldProductWidget({
    Key? key,
    required this.product,
    required this.soldQuantity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color coralColor = Color(0xFFFF7F50); // Coral color

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300), // Thin gray border
        borderRadius: BorderRadius.circular(8), // Smooth corners
      ),
      color: Colors.white, // White background for better contrast
      elevation: 2, // Slight elevation for depth
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            product.imageUrls.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: Image.network(
                      product.imageUrls.first,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image_not_supported,
                        color: Colors.grey.shade400),
                  ),
            SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Most Sold Product',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      )),
                  SizedBox(height: 4.0),
                  Text(product.productName,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      )),
                  SizedBox(height: 4.0),
                  Text('Price: ${product.price.toString()} ${product.currency}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      )),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$soldQuantity sold',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: coralColor,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8.0),
                RatingBarIndicator(
                  rating: product.averageRating,
                  itemBuilder: (context, index) => Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  itemSize: 16.0,
                ),
                Text(
                  '(${product.reviewCount})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
