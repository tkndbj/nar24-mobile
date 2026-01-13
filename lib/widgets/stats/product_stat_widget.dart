// lib/widgets/stats/product_stat_widget.dart

import 'package:flutter/material.dart';
import '../../models/product.dart';

class ProductStatWidget extends StatelessWidget {
  final String title;
  final Product product;
  final String value;

  const ProductStatWidget({
    Key? key,
    required this.title,
    required this.product,
    required this.value,
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
                  Text(title,
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
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: coralColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
