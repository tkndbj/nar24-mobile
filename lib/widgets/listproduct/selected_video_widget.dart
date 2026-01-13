import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'video_player_widget.dart';

class SelectedVideoWidget extends StatelessWidget {
  final XFile? videoFile;
  final VoidCallback onRemoveVideo;

  const SelectedVideoWidget({
    Key? key,
    required this.videoFile,
    required this.onRemoveVideo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If no video selected, return an empty widget
    if (videoFile == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          // Uses the updated VideoPlayerWidget which does NOT autoplay
          child: VideoPlayerWidget(file: File(videoFile!.path)),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: onRemoveVideo,
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
  }
}
