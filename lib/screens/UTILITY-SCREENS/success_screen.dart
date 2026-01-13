import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({Key? key}) : super(key: key);

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with TickerProviderStateMixin {
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
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    _buildSuccessAnimation(),
                    const SizedBox(height: 40),
                    _buildSuccessMessage(l10n),
                    const SizedBox(height: 60),
                    _buildFeatureCard(l10n),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildActionButton(l10n),
          ],
        ),
      ),
    );
  }

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
                    width: 250,
                    height: 250,
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
                        width: 3,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background circle effect
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            color: _successColor.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Success icon
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _successColor,
                                _successColor.withOpacity(0.8)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _successColor.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
                  l10n.congratulationsSuccess,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.8,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    l10n.successDescription,
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

  Widget _buildFeatureCard(AppLocalizations l10n) => AnimatedBuilder(
        animation: _mainController,
        builder: (context, child) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primaryColor.withOpacity(0.08),
                    _primaryColor.withOpacity(0.04)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _primaryColor.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isDark ? Colors.black : Colors.grey)
                        .withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _primaryColor,
                              _primaryColor.withOpacity(0.8)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.shopping_bag_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.exploreMarketplace,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.marketplaceDescription,
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 14,
                                height: 1.4,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _primaryColor.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: _successColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.safeShoppingGuarantee,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                              height: 1.4,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildActionButton(AppLocalizations l10n) => _showButtons
      ? AnimatedBuilder(
          animation: _buttonController,
          builder: (context, child) => FadeTransition(
            opacity: _buttonFade,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isDark ? Colors.black : Colors.grey)
                        .withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  )
                ],
              ),
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00A86B), Color(0xFF00926B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    context.go('/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_bag_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        l10n.goToMarket,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
      : const SizedBox(height: 120);
}
