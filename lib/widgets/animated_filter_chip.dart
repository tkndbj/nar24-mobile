import 'package:flutter/material.dart';

class AnimatedFilterChip extends StatefulWidget {
  final String displayName;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const AnimatedFilterChip({
    Key? key,
    required this.displayName,
    required this.color,
    required this.isDark,
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedFilterChip> createState() => _AnimatedFilterChipState();
}

class _AnimatedFilterChipState extends State<AnimatedFilterChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    ));

    // Start the shimmer animation with a delay
    Future.delayed(
        Duration(milliseconds: 500 + (widget.displayName.hashCode % 1000)), () {
      if (mounted) {
        _controller.repeat(reverse: false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.color.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // Main content
                    Text(
                      widget.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),

                    // Shimmer effect overlay
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedBuilder(
                          animation: _shimmerAnimation,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  stops: [
                                    (_shimmerAnimation.value - 0.3)
                                        .clamp(0.0, 1.0),
                                    _shimmerAnimation.value.clamp(0.0, 1.0),
                                    (_shimmerAnimation.value + 0.3)
                                        .clamp(0.0, 1.0),
                                  ],
                                  colors: [
                                    Colors.transparent,
                                    widget.color.withOpacity(0.15),
                                    Colors.transparent,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
