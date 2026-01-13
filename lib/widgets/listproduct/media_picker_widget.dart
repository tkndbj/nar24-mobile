import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../generated/l10n/app_localizations.dart';

class MediaPickerWidget extends StatefulWidget {
  final XFile? videoFile;
  final List<XFile> imageFiles; // New images
  final List<String> existingImageUrls; // Existing image URLs

  /// Callback when user picks or captures a video.
  /// The ImageSource parameter indicates whether to use camera or gallery.
  final Future<void> Function(ImageSource source) onPickVideo;
  final VoidCallback onRemoveVideo;

  /// Callback when user picks or captures images.
  /// The ImageSource parameter indicates whether to use camera or gallery.
  final Future<void> Function(ImageSource source) onPickImages;
  final void Function(int) onRemoveImage; // For removing new images
  final void Function(String) onRemoveExistingImage; // For removing existing images

  static const int maxImages = 10;

  const MediaPickerWidget({
    Key? key,
    required this.videoFile,
    required this.imageFiles,
    required this.existingImageUrls,
    required this.onPickVideo,
    required this.onRemoveVideo,
    required this.onPickImages,
    required this.onRemoveImage,
    required this.onRemoveExistingImage,
  }) : super(key: key);

  @override
  State<MediaPickerWidget> createState() => _MediaPickerWidgetState();
}

class _MediaPickerWidgetState extends State<MediaPickerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoFile != null) {
      _initializeVideo(widget.videoFile!);
    }
  }

  @override
  void didUpdateWidget(MediaPickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoFile != widget.videoFile) {
      _disposeController();
      if (widget.videoFile != null) {
        _initializeVideo(widget.videoFile!);
      }
    }
  }

  void _initializeVideo(XFile videoFile) {
    final file = File(videoFile.path);
    _controller = VideoPlayerController.file(file)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller!.pause();
      });
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  // Show CupertinoActionSheet for video options
  void _showVideoOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPickVideo(ImageSource.gallery);
            },
            child: Text(
              l10n.pickFromGallery,
              style: TextStyle(color: textColor),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPickVideo(ImageSource.camera);
            },
            child: Text(
              l10n.captureVideo,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          isDestructiveAction: false,
          child: Text(
            l10n.cancel,
            style: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }

  // Show CupertinoActionSheet for image options
  void _showImageOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPickImages(ImageSource.gallery);
            },
            child: Text(
              l10n.pickFromGallery,
              style: TextStyle(color: textColor),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPickImages(ImageSource.camera);
            },
            child: Text(
              l10n.capturePhoto,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          isDestructiveAction: false,
          child: Text(
            l10n.cancel,
            style: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const double pickerSize = 80.0;
    const Color borderColor = Colors.grey;
    const Color videoIconColor = Color(0xFF26A69A);
    const Color cameraIconColor = Color(0xFFFFA726);

    List<Widget> mediaWidgets = [];

    // Video upload box (first position)
    mediaWidgets.add(
      GestureDetector(
        onTap: widget.videoFile == null
            ? () => _showVideoOptions(context)
            : null,
        child: Stack(
          children: [
            Container(
              width: pickerSize,
              height: pickerSize,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  widget.videoFile == null
                      ? Icon(
                          Icons.videocam,
                          size: 32,
                          color: videoIconColor,
                        )
                      : (_isInitialized && _controller != null
                          ? VideoPlayer(_controller!)
                          : const CircularProgressIndicator()),
                  const SizedBox(height: 4),
                  if (widget.videoFile == null)
                    Text(
                      l10n.addVideo,
                      style: const TextStyle(
                        fontSize: 12,
                        color: videoIconColor,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.videoFile != null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: widget.onRemoveVideo,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Existing image URLs
    for (int i = 0; i < widget.existingImageUrls.length; i++) {
      mediaWidgets.add(
        Stack(
          children: [
            Container(
              width: pickerSize,
              height: pickerSize,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
                image: DecorationImage(
                  image: NetworkImage(widget.existingImageUrls[i]),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => widget.onRemoveExistingImage(
                  widget.existingImageUrls[i],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // New image files
    for (int i = 0; i < widget.imageFiles.length; i++) {
      mediaWidgets.add(
        Stack(
          children: [
            Container(
              width: pickerSize,
              height: pickerSize,
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(6),
                image: DecorationImage(
                  image: FileImage(File(widget.imageFiles[i].path)),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => widget.onRemoveImage(i),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Add image picker box if limit not reached
    if (widget.existingImageUrls.length + widget.imageFiles.length <
        MediaPickerWidget.maxImages) {
      mediaWidgets.add(
        GestureDetector(
          onTap: () => _showImageOptions(context),
          child: Container(
            width: pickerSize,
            height: pickerSize,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt,
                  size: 32,
                  color: cameraIconColor,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.addImage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: cameraIconColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: pickerSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: mediaWidgets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) => mediaWidgets[index],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
