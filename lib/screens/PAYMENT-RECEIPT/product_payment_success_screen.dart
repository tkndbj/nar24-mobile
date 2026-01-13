import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../generated/l10n/app_localizations.dart';

class ProductPaymentSuccessScreen extends StatefulWidget {
  final Product? product; // Make nullable
  final String? productId; // Make nullable
  final String? orderId;

  const ProductPaymentSuccessScreen({
    Key? key,
    this.product, // Remove required
    this.productId, // Remove required
    this.orderId,
  }) : super(key: key);

  @override
  State<ProductPaymentSuccessScreen> createState() =>
      _ProductPaymentSuccessScreenState();
}

class _ProductPaymentSuccessScreenState
    extends State<ProductPaymentSuccessScreen> with TickerProviderStateMixin {
  late AnimationController _mainController, _buttonController, _pulseController;
  late Animation<double> _fade, _scale, _buttonFade, _pulse;
  late Animation<Offset> _slide;
  bool _showButtons = false;

  // Dark mode colors
  static const _darkPrimaryColor = Color(0xFF6366F1);
  static const _darkSuccessColor = Color(0xFF10B981);
  static const _darkSurfaceColor = Color(0xFF1C1A29);
  static const _darkCardColor = Color.fromARGB(255, 33, 31, 49);
  static const _darkTextPrimary = Colors.white;
  static const _darkTextSecondary = Colors.white70;
  static const _darkBorderColor = Color(0xFF3F3D56);

  // Light mode colors
  static const _lightPrimaryColor = Color(0xFF6366F1);
  static const _lightSuccessColor = Color(0xFF059669);
  static const _lightSurfaceColor = Color(0xFFFAFAFA);
  static const _lightCardColor = Colors.white;
  static const _lightTextPrimary = Color(0xFF1F2937);
  static const _lightTextSecondary = Color(0xFF6B7280);
  static const _lightBorderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimationSequence();
  }

  void _initializeAnimations() {
    _mainController = AnimationController(
        duration: const Duration(milliseconds: 1500), vsync: this);
    _buttonController = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this);
    _pulseController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);

    _fade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut)));
    _slide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)));
    _scale = Tween<double>(begin: 0.6, end: 1).animate(CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 1, curve: Curves.elasticOut)));
    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _buttonController, curve: Curves.easeOutCubic));
    _pulse = Tween<double>(begin: 1, end: 1.1).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  void _startAnimationSequence() async {
    await _mainController.forward();
    _pulseController.repeat(reverse: true);
    setState(() => _showButtons = true);
    await _buttonController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _buttonController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // Theme-aware color getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _primaryColor => _isDark ? _darkPrimaryColor : _lightPrimaryColor;
  Color get _successColor => _isDark ? _darkSuccessColor : _lightSuccessColor;
  Color get _surfaceColor => _isDark ? _darkSurfaceColor : _lightSurfaceColor;
  Color get _cardColor => _isDark ? _darkCardColor : _lightCardColor;
  Color get _textPrimary => _isDark ? _darkTextPrimary : _lightTextPrimary;
  Color get _textSecondary =>
      _isDark ? _darkTextSecondary : _lightTextSecondary;
  Color get _borderColor => _isDark ? _darkBorderColor : _lightBorderColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(l10n),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildSuccessAnimation(),
                    const SizedBox(height: 32),
                    _buildSuccessMessage(l10n),
                    const SizedBox(height: 32),
                    _buildProductCard(l10n),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildActionButtons(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(AppLocalizations l10n) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          boxShadow: [
            BoxShadow(
              color: (_isDark ? Colors.black : Colors.grey).withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: IconButton(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.close_rounded, size: 16),
                style: IconButton.styleFrom(
                  foregroundColor: _textSecondary,
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.paymentSuccess,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSuccessAnimation() => AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Transform.scale(
                  scale: _pulse.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _successColor.withOpacity(0.1),
                          _successColor.withOpacity(0.05)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _successColor.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 70,
                      color: _successColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildSuccessMessage(AppLocalizations l10n) => AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(
              children: [
                Text(
                  l10n.paymentSuccessful,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.6,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    l10n.thankYouForYourPurchase,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _textSecondary,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildProductCard(AppLocalizations l10n) => AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: (_isDark ? Colors.black : Colors.grey)
                        .withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.shopping_bag_rounded,
                      color: _primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.purchaseComplete,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.orderProcessedSuccessfully,
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _successColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildActionButtons(AppLocalizations l10n) => _showButtons
      ? AnimatedBuilder(
          animation: _buttonController,
          builder: (context, child) => FadeTransition(
            opacity: _buttonFade,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isDark ? Colors.black : Colors.grey)
                        .withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -3),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00A36C), Color(0xFF00926B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      onPressed: () => context.go("/"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_bag_rounded, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            l10n.goToMarket,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () =>
                          context.go('/receipts', extra: {'preventPop': true}),
                      style: TextButton.styleFrom(
                        foregroundColor: _textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_rounded, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            l10n.goToPaymentDetails,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      : const SizedBox(height: 100);
}
