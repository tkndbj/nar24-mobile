// lib/widgets/editproduct/existing_video_player_widget.dart

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ExistingVideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const ExistingVideoPlayerWidget({Key? key, required this.videoUrl})
      : super(key: key);

  @override
  State<ExistingVideoPlayerWidget> createState() =>
      _ExistingVideoPlayerWidgetState();
}

class _ExistingVideoPlayerWidgetState extends State<ExistingVideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.setLooping(true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _initialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : const Center(child: CircularProgressIndicator());
  }
}
