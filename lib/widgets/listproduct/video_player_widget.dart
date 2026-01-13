import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final File file;

  const VideoPlayerWidget({Key? key, required this.file}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.setLooping(true);
        // Remove the autoplay call:
        // _controller.play(); <-- Removed to avoid autoplay

        // Optionally keep the video paused initially:
        _controller.pause();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const CircularProgressIndicator();
    }

    // Wrap VideoPlayer in GestureDetector to toggle play/pause on tap
    return GestureDetector(
      onTap: _togglePlayPause,
      child: SizedBox(
        width: 150,
        height: 150,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
