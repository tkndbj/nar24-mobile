// lib/splash_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';

/// A lightweight, production-ready splash screen with animated typewriter effect.
/// Displays the app logo with an animated subtitle on a gradient background.
class VideoSplashScreen extends StatefulWidget {
  /// Optional callback when the splash should finish.
  final VoidCallback? onVideoFinish;

  const VideoSplashScreen({Key? key, this.onVideoFinish}) : super(key: key);

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  String _displayedText = '';
  final String _fullText = 'Ne Ararsan Rahatlıkla';
  Timer? _typingTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    // Initialize fade and scale animations for logo
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    // Start logo animation
    _controller.forward();

    // Start typewriter effect after logo animation
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _startTypewriterEffect();
      }
    });
  }

  void _startTypewriterEffect() {
    const typingSpeed = Duration(milliseconds: 80);
    _typingTimer = Timer.periodic(typingSpeed, (timer) {
      if (_currentIndex < _fullText.length) {
        if (mounted) {
          setState(() {
            _displayedText = _fullText.substring(0, _currentIndex + 1);
            _currentIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Responsive sizing - scale up on tablets
    final isTablet = screenWidth > 600;
    final logoSize = isTablet ? 350.0 : 250.0;
    final subtitleFontSize = isTablet ? 28.0 : 20.0;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF9800), // Orange
              Color(0xFFFF6B9D), // Pink
            ],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Logo
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Hero(
                      tag: 'app_logo',
                      child: SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Image.asset(
                          'assets/images/beyazlogo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            // Fallback in case image fails to load
                            return Container(
                              color: Colors.transparent,
                              child: const Icon(
                                Icons.shopping_bag,
                                size: 120,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: isTablet ? 30 : 20),

                // Animated Typewriter Subtitle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  height: isTablet ? 50 : 40,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _displayedText,
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                offset: const Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        // Blinking cursor
                        if (_currentIndex < _fullText.length)
                          _BlinkingCursor(
                            fontSize: subtitleFontSize,
                          ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: isTablet ? 40 : 25),

                // Subtle loading indicator
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: isTablet ? 50 : 40,
                    height: isTablet ? 50 : 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple blinking cursor widget for the typewriter effect
class _BlinkingCursor extends StatefulWidget {
  final double fontSize;

  const _BlinkingCursor({
    required this.fontSize,
  });

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 530),
      vsync: this,
    )..repeat(reverse: true);

    _blinkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _blinkController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _blinkAnimation,
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        width: 2,
        height: widget.fontSize,
        color: Colors.white,
      ),
    );
  }
}
