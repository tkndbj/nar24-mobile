import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class SelectedImagesWidget extends StatelessWidget {
  final List<XFile> imageFiles;
  final void Function(int) onRemoveImage;

  const SelectedImagesWidget({
    Key? key,
    required this.imageFiles,
    required this.onRemoveImage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return imageFiles.isNotEmpty
        ? SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: imageFiles.length,
              itemBuilder: (context, index) {
                final image = imageFiles[index];
                return Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      child: Image.file(
                        File(image.path),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => onRemoveImage(index),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          )
        : const SizedBox.shrink();
  }
}
