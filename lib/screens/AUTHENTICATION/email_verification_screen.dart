import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../user_provider.dart';
import 'package:provider/provider.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({Key? key}) : super(key: key);

  @override
  _EmailVerificationScreenState createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with SingleTickerProviderStateMixin {
  bool _isResending = false;
  bool _isVerifying = false;
  User? _currentUser;
  Timer? _countdownTimer;
  int _countdownSeconds = 0;

  // Code input controller
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();

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

    _codeFocusNode.addListener(() {
      setState(() {});
    });

    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser == null) {
      context.go('/login');
      return;
    }

    // Send verification code immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resendVerificationCode();
    });
  }

  void _startCountdownTimer() {
    _countdownSeconds = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 0) {
        setState(() {
          _countdownSeconds--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _resendVerificationCode() async {
    final l10n = AppLocalizations.of(context);
    if (_countdownSeconds > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseWaitBeforeResendingEmail(_countdownSeconds)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() {
      _isResending = true;
    });

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('resendEmailVerificationCode');

      await callable.call();

      _startCountdownTimer();
      _clearCodeInputs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(l10n.verificationCodeSent ??
                        'Verification code sent!')),
              ],
            ),
            backgroundColor: const Color(0xFF00A86B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        if (e.code == 'resource-exhausted') {
          final match = RegExp(r'(\d+)').firstMatch(e.message ?? '');
          if (match != null) {
            _countdownSeconds = int.tryParse(match.group(1) ?? '30') ?? 30;
            _countdownTimer?.cancel();
            _countdownTimer =
                Timer.periodic(const Duration(seconds: 1), (timer) {
              if (_countdownSeconds > 0) {
                setState(() {
                  _countdownSeconds--;
                });
              } else {
                timer.cancel();
              }
            });
          }
          return;
        }

        String message;
        switch (e.code) {
          case 'failed-precondition':
            message = e.message ?? 'Email already verified';
            break;
          default:
            message = '${l10n.error}: ${e.message}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
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

  void _clearCodeInputs() {
    _codeController.clear();
    _codeFocusNode.requestFocus();
  }

  String get _enteredCode => _codeController.text;

  bool get _isCodeComplete => _enteredCode.length == 6;

  Future<void> _verifyCode() async {
    if (!_isCodeComplete) return;

    setState(() {
      _isVerifying = true;
    });

    final l10n = AppLocalizations.of(context);

    try {
      final HttpsCallable callable =
          FirebaseFunctions.instanceFor(region: 'europe-west3')
              .httpsCallable('verifyEmailCode');

      await callable.call({'code': _enteredCode});

      await _currentUser?.reload();
      _currentUser = FirebaseAuth.instance.currentUser;

      if (mounted) {
        await Provider.of<UserProvider>(context, listen: false).refreshUser();
        _showSuccessAndNavigate();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        String message;
        switch (e.code) {
          case 'invalid-argument':
            message =
                l10n.invalidVerificationCode ?? 'Invalid verification code';
            break;
          case 'deadline-exceeded':
            message =
                l10n.verificationCodeExpired ?? 'Verification code has expired';
            break;
          case 'failed-precondition':
            message = l10n.verificationCodeUsed ??
                'Verification code has already been used';
            break;
          case 'not-found':
            message = l10n.noVerificationCode ?? 'No verification code found';
            break;
          default:
            message = '${l10n.error}: ${e.message}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );

        _clearCodeInputs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _clearCodeInputs();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  void _showSuccessAndNavigate() async {
    final l10n = AppLocalizations.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(l10n.emailVerified ?? 'Email verified successfully!'),
          ],
        ),
        backgroundColor: const Color(0xFF00A86B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _fadeInController.dispose();

    _codeController.dispose();
    _codeFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Header
                              _buildHeader(l10n, isDark),
                              const SizedBox(height: 32),

                              // Code input
                              _buildCodeInput(isDark),
                              const SizedBox(height: 24),

                              // Verify button
                              _buildVerifyButton(l10n, isDark),
                              const SizedBox(height: 12),

                              // Resend button
                              _buildResendButton(l10n, isDark),
                              const SizedBox(height: 20),

                              // Help text
                              _buildHelpText(l10n, isDark),
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
        children: [
          GestureDetector(
            onTap: () async {
              _countdownTimer?.cancel();
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                context.go('/login');
              }
            },
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
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        // Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00A86B), Color(0xFF00C853)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Text(
          l10n.emailVerificationTitle,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'Figtree',
            color: isDark ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Email display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _currentUser?.email ?? '',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
              fontFamily: 'Figtree',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Subtitle
        Text(
          l10n.enterVerificationCode ??
              'Enter the 6-digit code sent to your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white60 : Colors.black54,
            fontFamily: 'Figtree',
          ),
        ),
      ],
    );
  }

  Widget _buildCodeInput(bool isDark) {
    return GestureDetector(
      onTap: () => _codeFocusNode.requestFocus(),
      child: Stack(
        children: [
          // Visual digit boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              final code = _codeController.text;
              final hasValue = index < code.length;
              final isFocused = _codeFocusNode.hasFocus && index == code.length;
              return Container(
                width: 46,
                height: 54,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasValue
                        ? const Color(0xFF00A86B)
                        : isFocused
                            ? const Color(0xFF00A86B).withOpacity(0.5)
                            : (isDark ? Colors.white12 : Colors.grey.shade300),
                    width: hasValue ? 1.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  hasValue ? code[index] : '',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Figtree',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              );
            }),
          ),
          // Hidden TextField that handles all input
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _codeController,
                focusNode: _codeFocusNode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                enableInteractiveSelection: false,
                showCursor: false,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (value) {
                  setState(() {});
                  if (value.length == 6) {
                    _codeFocusNode.unfocus();
                    _verifyCode();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: (_isVerifying || !_isCodeComplete) ? null : _verifyCode,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00A86B),
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.shade200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isVerifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                l10n.verifyCode ?? 'Verify Code',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                ),
              ),
      ),
    );
  }

  Widget _buildResendButton(AppLocalizations l10n, bool isDark) {
    final isDisabled = _isResending || _countdownSeconds > 0;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: isDisabled ? null : _resendVerificationCode,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : Colors.black87,
          side: BorderSide(
            color: isDark ? Colors.white24 : Colors.grey.shade300,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _isResending
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              )
            : Text(
                _countdownSeconds > 0
                    ? '${l10n.resendCode ?? "Resend Code"} ($_countdownSeconds)'
                    : l10n.resendCode ?? 'Resend Code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Figtree',
                  color: isDisabled
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
      ),
    );
  }

  Widget _buildHelpText(AppLocalizations l10n, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.checkSpamFolder ??
                "Can't find the email? Check your spam folder.",
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
              fontFamily: 'Figtree',
            ),
          ),
        ),
      ],
    );
  }
}
