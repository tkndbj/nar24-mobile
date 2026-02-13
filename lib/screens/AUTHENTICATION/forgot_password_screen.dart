import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/language_selector.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _emailSent = false;
  bool _isResending = false;

  // Timer for resend functionality
  Timer? _resendTimer;
  int _resendCountdown = 0;
  static const int _resendCooldownSeconds = 60;

  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeOut,
    ));

    _fadeInController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _resendTimer?.cancel();
    _fadeInController.dispose();
    super.dispose();
  }

  // Dismiss keyboard when tapping outside
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = _resendCooldownSeconds;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _resendCountdown--;
      });

      if (_resendCountdown <= 0) {
        timer.cancel();
      }
    });
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.green
                  ? Icons.check_circle
                  : backgroundColor == Colors.red
                      ? Icons.error_outline
                      : Icons.info_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Figtree',
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor ?? const Color(0xFF00A86B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _sendPasswordResetEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim().toLowerCase();

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('sendPasswordResetEmail');
      await callable.call({'email': email});

      setState(() {
        _emailSent = true;
      });

      _startResendTimer();

      if (mounted) {
        final message = AppLocalizations.of(context).passwordResetSent ??
            'Password reset email sent! Check your inbox and follow the instructions to reset your password.';

        _showSnackBar(message, backgroundColor: Colors.green);
      }
    } on FirebaseFunctionsException catch (e) {
      String message;
      switch (e.code) {
        case 'invalid-argument':
          message = AppLocalizations.of(context).errorInvalidEmail ??
              'Please enter a valid email address.';
          break;
        default:
          message = AppLocalizations.of(context).errorGeneral ??
              'An error occurred. Please try again.';
      }

      if (mounted) {
        _showSnackBar(message, backgroundColor: Colors.red);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).errorGeneral ??
              'An error occurred. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendPasswordResetEmail() async {
    if (_resendCountdown > 0) return;

    setState(() {
      _isResending = true;
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('sendPasswordResetEmail');
      await callable
          .call({'email': _emailController.text.trim().toLowerCase()});

      _startResendTimer();

      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context).passwordResetResent ??
              'Password reset email sent again!',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Failed to resend email. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeInAnimation,
            child: Column(
              children: [
                // Top bar
                _buildTopBar(isDark),

                // Main content
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            children: [
                              const SizedBox(height: 32),

                              // Header with icon
                              _buildHeader(l10n, isDark),

                              const SizedBox(height: 32),

                              // Form or Success state
                              if (!_emailSent)
                                _buildEmailForm(l10n, isDark)
                              else
                                _buildSuccessState(l10n, isDark),

                              const SizedBox(height: 24),

                              // Info box
                              _buildInfoBox(l10n, isDark),

                              const SizedBox(height: 24),

                              // Back to login link
                              _buildBackToLogin(l10n, isDark),

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
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

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 18,
              ),
            ),
          ),
          // Language selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: LanguageSelector(
              iconColor: isDark ? Colors.white70 : Colors.black54,
              iconSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        // Icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color:
                isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.15)
                  : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Icon(
            _emailSent ? Icons.mark_email_read_outlined : Icons.lock_reset,
            size: 32,
            color: _emailSent
                ? const Color(0xFF00A86B)
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Text(
          _emailSent
              ? (l10n.checkYourEmail ?? 'Check Your Email')
              : (l10n.forgotPasswordTitle ?? 'Reset Password'),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'Figtree',
            color: isDark ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _emailSent
                ? (l10n.forgotPasswordSuccessSubtitle ??
                    'We\'ve sent a password reset link to your email. Check your inbox and follow the instructions.')
                : (l10n.forgotPasswordSubtitle ??
                    'Enter your email address and we\'ll send you a link to reset your password.'),
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black54,
              fontFamily: 'Figtree',
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailForm(AppLocalizations l10n, bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email label
          Text(
            l10n.emailLabel ?? 'Email',
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),

          // Email field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 15,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: l10n.emailHint ?? 'Enter your email',
              hintStyle: TextStyle(
                color: isDark ? Colors.white30 : Colors.black26,
                fontFamily: 'Figtree',
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.email_outlined,
                color: isDark ? Colors.white38 : Colors.black38,
                size: 20,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: const Color(0xFF00A86B).withOpacity(0.6),
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
              errorStyle: const TextStyle(fontSize: 11),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              isDense: true,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.emailErrorEmpty ?? 'Email is required';
              }
              bool emailValid =
                  RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim());
              if (!emailValid) {
                return l10n.emailErrorInvalid ?? 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Send button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _sendPasswordResetEmail,
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      l10n.sendResetEmailButton ?? 'Send Reset Link',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Figtree',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00A86B).withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          // Success icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF00A86B).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 32,
              color: Color(0xFF00A86B),
            ),
          ),
          const SizedBox(height: 16),

          // Email sent to label
          Text(
            l10n.emailSentTo ?? 'Email sent to:',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 6),

          // Email address
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _emailController.text.trim(),
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'Figtree',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Resend button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: (_resendCountdown > 0 || _isResending)
                  ? null
                  : _resendPasswordResetEmail,
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : Colors.black87,
                side: BorderSide(
                  color: (_resendCountdown > 0 || _isResending)
                      ? (isDark ? Colors.white30 : Colors.grey.shade300)
                      : (isDark ? Colors.white38 : Colors.grey.shade400),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isResending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.white54 : Colors.black38,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh,
                          color: (_resendCountdown > 0)
                              ? (isDark ? Colors.white38 : Colors.black26)
                              : (isDark ? Colors.white70 : Colors.black54),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _resendCountdown > 0
                              ? '${l10n.resendEmailButton ?? "Resend"} ($_resendCountdown s)'
                              : (l10n.resendEmailButton ?? 'Resend Email'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Figtree',
                            color: (_resendCountdown > 0)
                                ? (isDark ? Colors.white38 : Colors.black26)
                                : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.amber.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? Colors.white54 : Colors.amber.shade700,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.checkSpamFolder ??
                  'Can\'t find the email? Check your spam folder.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.amber.shade900,
                fontFamily: 'Figtree',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackToLogin(AppLocalizations l10n, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.rememberPasswordText ?? 'Remember your password?',
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
            fontFamily: 'Figtree',
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => context.pop(),
          child: Text(
            l10n.backToLoginText ?? 'Sign In',
            style: TextStyle(
              color: const Color(0xFF00A86B),
              fontFamily: 'Figtree',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
