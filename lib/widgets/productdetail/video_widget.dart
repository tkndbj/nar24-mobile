import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoWidget extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onClose;

  /// [videoUrl]: The URL of the video to be played.
  /// [onClose]: Callback invoked when user taps the "x" icon.
  const VideoWidget({
    Key? key,
    required this.videoUrl,
    required this.onClose,
  }) : super(key: key);

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  late VideoPlayerController _controller;

  // Whether we show the fullscreen icon in the middle
  bool _showFullscreenIcon = false;

  // Timer to hide the fullscreen icon after 2 seconds
  Timer? _overlayTimer;

  // Track the current drag offset for the floating box
  Offset _offset = const Offset(200, 50);

  @override
  void initState() {
    super.initState();

    // Initialize the video player
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..addListener(() {
        if (mounted) {
          setState(() {});
        }
      })
      ..setLooping(true)
      ..initialize().then((_) {
        // Start playback once initialized
        _controller.play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Toggle the fullscreen icon overlay on/off.
  /// If turning on, schedule a timer to hide it after 2 seconds.
  void _toggleFullscreenIcon() {
    setState(() {
      _showFullscreenIcon = !_showFullscreenIcon;
    });

    if (_showFullscreenIcon) {
      _overlayTimer?.cancel();
      _overlayTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showFullscreenIcon = false;
          });
        }
      });
    }
  }

  /// Opens a fullscreen page containing the same video controller.
  /// The video won't restart from scratch because we pass the same controller.
  Future<void> _openFullScreen() async {
    // Cancel any existing timer
    _overlayTimer?.cancel();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenVideoPlayer(controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          // Drag to move the floating box around
          setState(() {
            _offset += details.delta;
          });
        },
        onTap: () {
          // If the fullscreen icon is already showing, tapping again
          // will open fullscreen.
          if (_showFullscreenIcon) {
            _openFullScreen();
          } else {
            _toggleFullscreenIcon();
          }
        },
        child: SizedBox(
          width: 160,
          height: 90, // Fixed horizontal rectangle
          child: Stack(
            children: [
              // The video itself, forced into 16:9 ratio (letterboxes if vertical)
              Container(
                width: 160,
                height: 90,
                color: Colors.black,
                child: _controller.value.isInitialized
                    ? Center(
                        // Always keep 16:9 inside our 160×90 box
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: VideoPlayer(_controller),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),

              // The always-visible "x" (close) icon in the top-right
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: widget.onClose,
                  splashColor: Colors.transparent, // no ripple
                  highlightColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),

              // The fullscreen icon in the center, only visible if _showFullscreenIcon == true
              if (_showFullscreenIcon)
                Center(
                  child: Icon(
                    Icons.fullscreen,
                    color: Colors.white.withOpacity(0.8),
                    size: 30,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full screen page that uses the same [VideoPlayerController].
/// This means the video won't restart from scratch.
class _FullScreenVideoPlayer extends StatelessWidget {
  final VideoPlayerController controller;

  const _FullScreenVideoPlayer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: controller.value.isInitialized
            ? AspectRatio(
                // In fullscreen, we respect the actual video aspect ratio
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
