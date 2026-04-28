// lib/widgets/coupon_celebration_overlay.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/coupon_service.dart';
import '../generated/l10n/app_localizations.dart';

/// A Temu-style coupon celebration overlay that shows when user has coupons.
///
/// Features:
/// - Smooth slide-up animation from bottom
/// - Pulsing/breathing animation on the coupon image
/// - Semi-transparent dark overlay background
/// - Dismissible with X button
/// - Only shows if user has active coupons that have not yet been celebrated
///
/// "Celebrated" state lives on the Firestore coupon document itself
/// (`celebratedAt`), so the overlay is correctly suppressed across devices and
/// reinstalls — not in SharedPreferences.
///
/// Usage: Call `CouponCelebrationOverlay.showIfEligible(context)` from market_screen
class CouponCelebrationOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const CouponCelebrationOverlay({
    Key? key,
    required this.onDismiss,
  }) : super(key: key);

  /// Shows the overlay if conditions are met (user has uncelebrated active
  /// coupons). Returns true if the overlay was shown, false otherwise.
  static Future<bool> showIfEligible(BuildContext context) async {
    // Safety check
    if (!context.mounted) return false;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) debugPrint('🎟️ Coupon overlay: No user logged in');
        return false;
      }

      final couponService = CouponService();
      final newCouponIds = await _getUncelebratedCouponIds(couponService);

      if (newCouponIds.isEmpty) {
        if (kDebugMode) {
          debugPrint('🎟️ Coupon overlay: No new coupons to celebrate');
        }
        return false;
      }

      if (!context.mounted) return false;

      if (kDebugMode) {
        debugPrint(
            '🎟️ Coupon overlay: Showing celebration for ${newCouponIds.length} new coupons');
      }

      await _showOverlay(context, couponService, newCouponIds);
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('🎟️ Coupon overlay error: $e');
        debugPrint('Stack: $stackTrace');
      }
      return false;
    }
  }

  /// Returns the IDs of active (unused, not expired) coupons that have not
  /// yet been marked celebrated on the server.
  static Future<Set<String>> _getUncelebratedCouponIds(
      CouponService service) async {
    try {
      // Wait for the coupon service stream to deliver its first snapshot
      // (max 3 seconds).
      int attempts = 0;
      while (!service.isInitialized && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (!service.isInitialized) {
        if (kDebugMode) {
          debugPrint('🎟️ CouponService not initialized after 3s');
        }
        return {};
      }

      final now = DateTime.now();
      return service.userCoupons
          .where((coupon) {
            if (coupon.isUsed) return false;
            if (coupon.celebratedAt != null) return false;
            if (coupon.expiresAt != null &&
                coupon.expiresAt!.toDate().isBefore(now)) {
              return false;
            }
            return true;
          })
          .map((coupon) => coupon.id)
          .toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('🎟️ Error checking coupons: $e');
      return {};
    }
  }

  /// Shows the overlay using Navigator
  static Future<void> _showOverlay(
    BuildContext context,
    CouponService couponService,
    Set<String> newCouponIds,
  ) async {
    final completer = Completer<void>();

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => CouponCelebrationOverlay(
          onDismiss: () async {
            // Persist the "celebrated" state on the Firestore docs themselves
            // so this overlay is suppressed across devices/reinstalls.
            // Fire-and-forget: pop immediately so the UI feels responsive,
            // but await the write to surface errors in debug.
            final writeFuture =
                couponService.markCelebrated(couponIds: newCouponIds);

            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            if (!completer.isCompleted) {
              completer.complete();
            }

            try {
              await writeFuture;
              if (kDebugMode) {
                debugPrint('🎟️ Marked as celebrated: $newCouponIds');
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('🎟️ Failed to mark celebrated: $e');
              }
            }
          },
        ),
      ),
    );

    return completer.future;
  }

  @override
  State<CouponCelebrationOverlay> createState() =>
      _CouponCelebrationOverlayState();
}

class _CouponCelebrationOverlayState extends State<CouponCelebrationOverlay>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _overlayController;
  late AnimationController _shimmerController;

  // Animations
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _overlayAnimation;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _scaleAnimation;

  bool _isDisposed = false;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimations();
  }

  void _initializeAnimations() {
    // 1. Overlay fade-in controller (background)
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOut,
    );

    // 2. Slide-up controller (coupon card)
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5), // Start from below screen
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // 3. Scale animation (bouncy entrance)
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // 4. Pulse/breathing animation (continuous)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // 5. Shimmer animation (sparkle effect)
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _shimmerAnimation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    ));
  }

  void _startAnimations() {
    // Sequence the animations
    _overlayController.forward();

    // Small delay before slide-up
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isDisposed && mounted) {
        _slideController.forward();
      }
    });

    // Start pulse after slide completes
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!_isDisposed && mounted) {
        _pulseController.repeat(reverse: true);
        _shimmerController.repeat();
      }
    });
  }

  Future<void> _handleDismiss() async {
    if (_isDismissing || _isDisposed) return;
    _isDismissing = true;

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Reverse animations
    _pulseController.stop();
    _shimmerController.stop();

    await Future.wait([
      _slideController.reverse(),
      _overlayController.reverse(),
    ]);

    if (!_isDisposed && mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _slideController.dispose();
    _pulseController.dispose();
    _overlayController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final size = MediaQuery.of(context).size;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dark overlay background
          _buildOverlayBackground(),

          // Coupon card content
          _buildCouponContent(l10n, size),

          // Close button
          _buildCloseButton(),

          // Floating particles/confetti effect
          _buildParticles(),
        ],
      ),
    );
  }

  Widget _buildOverlayBackground() {
    return AnimatedBuilder(
      animation: _overlayAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: _handleDismiss,
          child: Container(
            color: Colors.black.withOpacity(0.7 * _overlayAnimation.value),
          ),
        );
      },
    );
  }

  Widget _buildCouponContent(AppLocalizations l10n, Size size) {
    return Center(
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Coupon image with shimmer effect
                _buildCouponImage(size),

                const SizedBox(height: 24),

                // Celebration text
                _buildCelebrationText(l10n),

                const SizedBox(height: 16),

                // Subtitle
                _buildSubtitle(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCouponImage(Size size) {
    final imageSize = size.width * 0.7;

    return Container(
      width: imageSize,
      height: imageSize * 0.7,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
          BoxShadow(
            color: Colors.pink.withOpacity(0.3),
            blurRadius: 40,
            spreadRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Main coupon image
            Image.asset(
              'assets/images/coupon.png',
              fit: BoxFit.cover,
              width: imageSize,
              height: imageSize * 0.7,
              errorBuilder: (context, error, stackTrace) {
                // Fallback if image not found
                return Container(
                  width: imageSize,
                  height: imageSize * 0.7,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange, Colors.pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.card_giftcard,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),

            // Shimmer overlay effect (transparent gradient only)
            AnimatedBuilder(
              animation: _shimmerAnimation,
              builder: (context, child) {
                return Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        begin:
                            Alignment(-2.0 + _shimmerAnimation.value * 2, -0.3),
                        end: Alignment(-1.0 + _shimmerAnimation.value * 2, 0.3),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCelebrationText(AppLocalizations l10n) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.orange, Colors.pink, Colors.orange],
      ).createShader(bounds),
      child: Text(
        l10n.youHaveACoupon ?? '🎉 You have a coupon!',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSubtitle(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        l10n.couponWaitingForYou ??
            'A special discount is waiting for you in your cart!',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white.withOpacity(0.9),
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCloseButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: FadeTransition(
        opacity: _overlayAnimation,
        child: GestureDetector(
          onTap: _handleDismiss,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParticles() {
    return FadeTransition(
      opacity: _overlayAnimation,
      child: IgnorePointer(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _ParticlePainter(
              animation: _shimmerController,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for floating particle effects
class _ParticlePainter extends CustomPainter {
  final Animation<double> animation;
  final List<_Particle> _particles = [];
  final math.Random _random = math.Random(42); // Fixed seed for consistency

  _ParticlePainter({required this.animation}) : super(repaint: animation) {
    // Generate particles once
    for (int i = 0; i < 20; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 6 + 2,
        speed: _random.nextDouble() * 0.5 + 0.5,
        color: [
          Colors.orange.withOpacity(0.6),
          Colors.pink.withOpacity(0.6),
          Colors.yellow.withOpacity(0.6),
          Colors.white.withOpacity(0.4),
        ][_random.nextInt(4)],
      ));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in _particles) {
      final offset = (animation.value * particle.speed) % 1.0;
      final y = (particle.y + offset) % 1.0;

      final paint = Paint()
        ..color = particle.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.color,
  });
}
