import 'package:flutter/material.dart';

class CouponWidget extends StatelessWidget {
  final String leftText;
  final String discount;
  final String subtitle;
  final String validUntil;
  final String code;
  final Color primaryColor;
  final Color accentColor;
  final double width;
  final double height;

  const CouponWidget({
    super.key,
    this.leftText = 'Enjoy Your Gift',
    this.discount = '50% OFF',
    this.subtitle = 'Coupon',
    this.validUntil = 'Valid until May, 2023',
    this.code = '87878521112',
    this.primaryColor = const Color(0xFFFFD700), // Gold
    this.accentColor = Colors.black,
    this.width = 360,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(
          painter: _CouponPainter(
            primaryColor: primaryColor,
            notchRadius: 20,
          ),
          child: Row(
            children: [
              // Left Section
              _buildLeftSection(),
              // Center Section
              _buildCenterSection(),
              // Right Section
              _buildRightSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftSection() {
    return SizedBox(
      width: width * 0.18,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Colors.black.withValues(alpha: 0.15),
              width: 2,
              style: BorderStyle.solid,
            ),
          ),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                leftText.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterSection() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: accentColor,
              child: Text(
                discount.toUpperCase(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle.toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              validUntil.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.7),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSection() {
    return Container(
      width: width * 0.25,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            code,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: Colors.black87,
              fontFamily: 'Courier', // Monospace as fallback for barcode look
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }
}

class _CouponPainter extends CustomPainter {
  final Color primaryColor;
  final double notchRadius;

  _CouponPainter({
    required this.primaryColor,
    required this.notchRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final path = Path();

    // Start from top-left
    path.moveTo(0, 0);

    // Top edge
    path.lineTo(size.width, 0);

    // Right edge with notch
    path.lineTo(size.width, size.height / 2 - notchRadius);
    path.arcToPoint(
      Offset(size.width, size.height / 2 + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Left edge with notch
    path.lineTo(0, size.height / 2 + notchRadius);
    path.arcToPoint(
      Offset(0, size.height / 2 - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    path.lineTo(0, 0);

    path.close();
    canvas.drawPath(path, paint);

    // Draw white section on the right
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final whitePath = Path();
    final whiteStartX = size.width * 0.75;

    whitePath.moveTo(whiteStartX, 0);
    whitePath.lineTo(size.width, 0);
    whitePath.lineTo(size.width, size.height / 2 - notchRadius);
    whitePath.arcToPoint(
      Offset(size.width, size.height / 2 + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );
    whitePath.lineTo(size.width, size.height);
    whitePath.lineTo(whiteStartX, size.height);
    whitePath.close();

    canvas.drawPath(whitePath, whitePaint);
  }

  @override
  bool shouldRepaint(covariant _CouponPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.notchRadius != notchRadius;
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 6.0;
    const dashSpace = 4.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width - 1, startY),
        Offset(size.width - 1, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Example usage widget for preview
class CouponPreview extends StatelessWidget {
  const CouponPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue[200],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Default coupon
            const CouponWidget(),

            const SizedBox(height: 32),

            // Custom styled coupon
            CouponWidget(
              leftText: 'Special Deal',
              discount: '25% OFF',
              subtitle: 'Welcome',
              validUntil: 'Valid until Dec, 2024',
              code: '12345678900',
              primaryColor: Colors.deepOrange.shade400,
              width: 340,
              height: 150,
            ),
          ],
        ),
      ),
    );
  }
}
