// lib/widgets/editproduct/color_images_section.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ColorImagesSection extends StatelessWidget {
  final Map<String, List<String>> existingColorImages;
  final Map<String, List<XFile>> newColorImages;
  final Function(String color) addColorOption;
  final Function(String color) removeColorOption;
  final Function(String color) pickColorImages;
  final Function(String color, String url) removeExistingColorImage;
  final Function(String color, XFile file) removeNewColorImage;

  const ColorImagesSection({
    Key? key,
    required this.existingColorImages,
    required this.newColorImages,
    required this.addColorOption,
    required this.removeColorOption,
    required this.pickColorImages,
    required this.removeExistingColorImage,
    required this.removeNewColorImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Color Options',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        // Quick "Add Color" row
        Wrap(
          spacing: 8,
          children: [
            _buildAddColorButton('Red'),
            _buildAddColorButton('Blue'),
            _buildAddColorButton('Green'),
            _buildAddColorButton('Yellow'),
            _buildAddColorButton('Orange'),
            _buildAddColorButton('Black'),
            _buildAddColorButton('White'),
            _buildAddColorButton('Pink'),
            _buildAddColorButton('Gray'),
            _buildAddColorButton('Purple'),
          ],
        ),
        const SizedBox(height: 16),
        // Display existing + newly added color blocks
        ...existingColorImages.keys.map(
          (color) => _buildColorBlock(context, color),
        ),
        // Also show newly added color blocks if they had no existing images
        ...newColorImages.keys
            .where((c) => !existingColorImages.containsKey(c))
            .map(
              (color) => _buildColorBlock(context, color),
            ),
      ],
    );
  }

  Widget _buildAddColorButton(String colorName) {
    final alreadyUsed = existingColorImages.containsKey(colorName) ||
        newColorImages.containsKey(colorName);

    return ElevatedButton(
      onPressed: alreadyUsed ? null : () => addColorOption(colorName),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      child: Text(colorName),
    );
  }

  Widget _buildColorBlock(BuildContext context, String color) {
    final existingUrls = existingColorImages[color] ?? [];
    final newFiles = newColorImages[color] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _getColorFromName(color),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(color, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => removeColorOption(color),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Existing images
        if (existingUrls.isNotEmpty)
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: existingUrls.map((url) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      child: Image.network(
                        url,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => removeExistingColorImage(color, url),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

        // New images
        if (newFiles.isNotEmpty)
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: newFiles.map((file) {
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      child: Image.file(
                        File(file.path),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => removeNewColorImage(color, file),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

        const SizedBox(height: 8),

        // Button to pick images for this color
        ElevatedButton.icon(
          onPressed: () => pickColorImages(color),
          icon: const Icon(Icons.color_lens_outlined),
          label: const Text('Pick Images'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A86B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
        const Divider(thickness: 1),
      ],
    );
  }

  /// Convert color name to actual [Color]
  Color _getColorFromName(String color) {
    switch (color.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      case 'pink':
        return Colors.pink;
      case 'gray':
        return Colors.grey;
      case 'purple':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
