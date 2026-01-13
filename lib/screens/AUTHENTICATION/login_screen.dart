// lib/screens/auth/login_screen.dart

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth_service.dart';
import 'package:go_router/go_router.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/agreement_modal.dart';
import 'package:provider/provider.dart';
import '../../user_provider.dart';
import '../../utils/input_validator.dart';
import '../../utils/network_utils.dart';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final bool showVerificationMessage;
  final String? email;
  final String? password;

  const LoginScreen({
    Key? key,
    this.onLoginSuccess,
    this.showVerificationMessage = false,
    this.email,
    this.password,
  }) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isPasswordVisible = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  List<Timer> _activeTimers = [];

  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isResending = false;
  bool _showVerificationMessage = false;
  bool _twoFAPending = false;

  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    if (widget.email != null) {
      _emailController.text = widget.email!;
    }
    if (widget.password != null) {
      _passwordController.text = widget.password!;
    }
    _showVerificationMessage = widget.showVerificationMessage;

    // Initialize fade animation
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
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _fadeInController.dispose();
    super.dispose();
  }

  void _showFloatingSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.red
                  ? Icons.error_outline
                  : backgroundColor == Colors.green
                      ? Icons.check_circle
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
        backgroundColor: backgroundColor ?? const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _loginWithPassword() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Check connectivity before attempting login
        final hasConnection = await NetworkUtils.hasConnectivity();
        if (!hasConnection) {
          if (mounted) {
            _showFloatingSnackBar(
              AppLocalizations.of(context).errorNoConnection ??
                  'No internet connection. Please check your network and try again.',
              backgroundColor: Colors.red,
            );
          }
          return;
        }

        // Normalize email before login
        final normalizedEmail =
            InputValidator.normalizeEmail(_emailController.text);

        final result = await _authService.signInWithEmailAndPassword(
          normalizedEmail,
          _passwordController.text,
        );

        final User? user = result['user'];
        final bool needsComplete = result['needsCompletion'] ?? false;
        final bool needs2FA = result['needs2FA'] ?? false;

        if (user != null) {
          // Check if 2FA verification is needed
          if (needs2FA) {
            setState(() => _twoFAPending = true);
            // Navigate to 2FA verification screen
            final verificationResult = await context.push<bool>(
              '/two_factor_verification',
              extra: {
                'type': 'login',
              },
            );

            if (verificationResult == true) {
              if (!mounted) return;
              setState(() => _twoFAPending = false);
              await _authService.ensureFcmRegistered();
              // 2FA verified successfully
              if (!mounted) return;
              final userProvider =
                  Provider.of<UserProvider>(context, listen: false);
              await userProvider.updateUserDataImmediately(user,
                  profileComplete: !needsComplete);

              // Navigate to home - profile completion is optional
              if (!mounted) return;
              if (widget.onLoginSuccess != null) {
                widget.onLoginSuccess!();
              } else {
                context.go('/');
              }
            } else {
              // 2FA verification failed or cancelled
              if (mounted) {
                _showFloatingSnackBar(
                  AppLocalizations.of(context).twoFactorFailedMessage ??
                      'Two-factor authentication failed. Please try again.',
                  backgroundColor: Colors.red,
                );
              }
            }
            return;
          }

          // Normal login flow (no 2FA needed)
          if (!mounted) return;
          final userProvider =
              Provider.of<UserProvider>(context, listen: false);
          await userProvider.updateUserDataImmediately(user,
              profileComplete: !needsComplete);

          // Navigate to home - profile completion is optional
          if (!mounted) return;
          if (widget.onLoginSuccess != null) {
            widget.onLoginSuccess!();
          } else {
            context.go('/');
          }
        }
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        String message;
        switch (e.code) {
          case 'email-not-verified':
            // Navigate to email verification screen
            context.go('/email-verification');
            return;
          case 'user-not-found':
            message = AppLocalizations.of(context).errorUserNotFound ??
                'No user found with this email.';
            break;
          case 'wrong-password':
            message = AppLocalizations.of(context).errorWrongPassword ??
                'Incorrect password.';
            break;
          case 'invalid-email':
            message = AppLocalizations.of(context).errorInvalidEmail ??
                'Invalid email address.';
            break;
          case 'network-error':
            message = AppLocalizations.of(context).errorNetwork ??
                'Network error. Please check your connection and try again.';
            break;
          case 'too-many-requests':
          case 'too-many-attempts':
            message = AppLocalizations.of(context).errorTooManyAttempts ??
                'Too many failed attempts. Please try again later.';
            break;
          default:
            message = AppLocalizations.of(context).errorGeneral ??
                'An error occurred. Please try again.';
        }
        _showFloatingSnackBar(message, backgroundColor: Colors.red);
      } on TimeoutException {
        if (mounted) {
          _showFloatingSnackBar(
            AppLocalizations.of(context).errorTimeout ??
                'Request timed out. Please check your connection and try again.',
            backgroundColor: Colors.red,
          );
        }
      } catch (e) {
        if (mounted) {
          // Check if it's a network-related error
          final message = NetworkUtils.isNetworkError(e)
              ? (AppLocalizations.of(context).errorNetwork ??
                  'Network error. Please check your connection and try again.')
              : (AppLocalizations.of(context).errorGeneral ??
                  'An error occurred. Please try again.');
          _showFloatingSnackBar(message, backgroundColor: Colors.red);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
    });
    try {
      // Normalize email for resend
      final normalizedEmail =
          InputValidator.normalizeEmail(_emailController.text);

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: _passwordController.text,
      );
      User? user = userCredential.user;

      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        if (mounted) {
          _showFloatingSnackBar(
            AppLocalizations.of(context).verificationEmailSent ??
                'Verification email sent successfully!',
            backgroundColor: Colors.green,
          );
        }
      }
      await _authService.logout();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = AppLocalizations.of(context).errorUserNotFound ??
              'No user found with this email.';
          break;
        case 'wrong-password':
          message = AppLocalizations.of(context).errorWrongPassword ??
              'Incorrect password.';
          break;
        case 'invalid-email':
          message = AppLocalizations.of(context).errorInvalidEmail ??
              'Invalid email address.';
          break;
        case 'too-many-requests':
          message = AppLocalizations.of(context).errorTooManyAttempts ??
              'Too many attempts. Please try again later.';
          break;
        default:
          message = AppLocalizations.of(context).errorGeneral ??
              'An error occurred. Please try again.';
      }
      _showFloatingSnackBar(message, backgroundColor: Colors.red);
    } catch (_) {
      if (mounted) {
        _showFloatingSnackBar(
          AppLocalizations.of(context).errorGeneral ??
              'An error occurred. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      // Check connectivity before attempting Google Sign-In
      final hasConnection = await NetworkUtils.hasConnectivity();
      if (!hasConnection) {
        if (mounted) {
          _showFloatingSnackBar(
            AppLocalizations.of(context).errorNoConnection ??
                'No internet connection. Please check your network and try again.',
            backgroundColor: Colors.red,
          );
        }
        return;
      }

      final result =
          await _authService.signInWithGoogle(forceAccountPicker: true);
      final User? user = result['user'];
      final bool needsComplete = result['needsCompletion'] ?? false;
      final bool needs2FA = result['needs2FA'] ?? false;

      if (user != null) {
        // Check if 2FA verification is needed
        if (needs2FA) {
          setState(() => _twoFAPending = true);
          // Navigate to 2FA verification screen
          final verificationResult = await context.push<bool>(
            '/two_factor_verification',
            extra: {
              'type': 'login',
            },
          );

          if (verificationResult == true) {
            if (!mounted) return;
            setState(() => _twoFAPending = false);
            await _authService.ensureFcmRegistered();
            // 2FA verified successfully
            if (!mounted) return;
            final userProvider =
                Provider.of<UserProvider>(context, listen: false);
            await userProvider.updateUserDataImmediately(user,
                profileComplete: !needsComplete);

            // Show agreement modal for Google users who haven't accepted yet
            if (!mounted) return;
            final hasAccepted =
                await AgreementModal.hasAcceptedAgreements(user.uid);
            if (!hasAccepted && mounted) {
              await AgreementModal.show(context);
            }

            // Navigate to home - profile completion is optional
            if (!mounted) return;
            if (widget.onLoginSuccess != null) {
              widget.onLoginSuccess!();
            } else {
              context.go('/');
            }
          } else {
            // 2FA verification failed or cancelled
            if (mounted) {
              _showFloatingSnackBar(
                AppLocalizations.of(context).twoFactorFailedMessage ??
                    'Two-factor authentication failed. Please try again.',
                backgroundColor: Colors.red,
              );
            }
          }
          return;
        }

        // Normal Google login flow (no 2FA needed)
        if (!mounted) return;
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.updateUserDataImmediately(user,
            profileComplete: !needsComplete);

        // Show agreement modal for Google users who haven't accepted yet
        if (!mounted) return;
        final hasAccepted =
            await AgreementModal.hasAcceptedAgreements(user.uid);
        if (!hasAccepted && mounted) {
          await AgreementModal.show(context);
        }

        // Navigate to home - profile completion is optional
        if (!mounted) return;
        if (widget.onLoginSuccess != null) {
          widget.onLoginSuccess!();
        } else {
          context.go('/');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'network-error':
          message = AppLocalizations.of(context).errorNetwork ??
              'Network error. Please check your connection and try again.';
          break;
        case 'account-exists-with-different-credential':
          message = AppLocalizations.of(context).errorAccountExists ??
              'An account already exists with this email using a different sign-in method.';
          break;
        default:
          message = e.message ??
              AppLocalizations.of(context).errorGeneral ??
              'Google sign-in failed. Please try again.';
      }

      _showFloatingSnackBar(
        message,
        backgroundColor: Colors.red,
      );
    } on TimeoutException {
      if (mounted) {
        _showFloatingSnackBar(
          AppLocalizations.of(context).errorTimeout ??
              'Request timed out. Please check your connection and try again.',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) {
        // Check if it's a network-related error
        final message = NetworkUtils.isNetworkError(e)
            ? (AppLocalizations.of(context).errorNetwork ??
                'Network error. Please check your connection and try again.')
            : (AppLocalizations.of(context).errorGeneral ??
                'An error occurred. Please try again.');
        _showFloatingSnackBar(message, backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);

    try {
      // Check connectivity before attempting Apple Sign-In
      final hasConnection = await NetworkUtils.hasConnectivity();
      if (!hasConnection) {
        if (mounted) {
          _showFloatingSnackBar(
            AppLocalizations.of(context).errorNoConnection ??
                'No internet connection. Please check your network and try again.',
            backgroundColor: Colors.red,
          );
        }
        return;
      }

      final result = await _authService.signInWithApple();
      final User? user = result['user'];
      final bool needsComplete = result['needsCompletion'] ?? false;
      final bool needsName = result['needsName'] ?? false;
      final bool needs2FA = result['needs2FA'] ?? false;

      if (user != null) {
        // Check if 2FA verification is needed
        if (needs2FA) {
          setState(() => _twoFAPending = true);
          final verificationResult = await context.push<bool>(
            '/two_factor_verification',
            extra: {
              'type': 'login',
            },
          );

          if (verificationResult == true) {
            if (!mounted) return;
            setState(() => _twoFAPending = false);
            await _authService.ensureFcmRegistered();

            if (!mounted) return;
            final userProvider =
                Provider.of<UserProvider>(context, listen: false);
            await userProvider.updateUserDataImmediately(user,
                profileComplete: !needsComplete);

            // ✅ FIX: Set name completion state for router redirect
            if (needsName) {
              userProvider.setNameComplete(false);
            }

            if (!mounted) return;
            final hasAccepted =
                await AgreementModal.hasAcceptedAgreements(user.uid);
            if (!hasAccepted && mounted) {
              await AgreementModal.show(context);
            }

            // Navigate to home - router will redirect to complete-name if needed
            if (!mounted) return;
            if (widget.onLoginSuccess != null) {
              widget.onLoginSuccess!();
            } else {
              context.go('/');
            }
          } else {
            if (mounted) {
              _showFloatingSnackBar(
                AppLocalizations.of(context).twoFactorFailedMessage ??
                    'Two-factor authentication failed. Please try again.',
                backgroundColor: Colors.red,
              );
            }
          }
          return;
        }

        // ✅ FIX: REMOVED the manual navigation to /complete-name
        // The router redirect will handle this automatically
        // This prevents duplicate screens from appearing

        // Normal Apple login flow
        if (!mounted) return;
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.updateUserDataImmediately(user,
            profileComplete: !needsComplete);

        // ✅ FIX: Set name completion state so router knows to redirect
        if (needsName) {
          userProvider.setNameComplete(false);
        }

        // Show agreement modal for Apple users who haven't accepted yet
        if (!mounted) return;
        final hasAccepted =
            await AgreementModal.hasAcceptedAgreements(user.uid);
        if (!hasAccepted && mounted) {
          await AgreementModal.show(context);
        }

        // Navigate to home - router will redirect to /complete-name if needsName
        if (!mounted) return;
        if (widget.onLoginSuccess != null) {
          widget.onLoginSuccess!();
        } else {
          context.go('/');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message;
      switch (e.code) {
        case 'network-error':
          message = AppLocalizations.of(context).errorNetwork ??
              'Network error. Please check your connection and try again.';
          break;
        case 'account-exists-with-different-credential':
          message = AppLocalizations.of(context).errorAccountExists ??
              'An account already exists with this email using a different sign-in method.';
          break;
        default:
          message = e.message ??
              AppLocalizations.of(context).errorGeneral ??
              'Apple sign-in failed. Please try again.';
      }

      _showFloatingSnackBar(
        message,
        backgroundColor: Colors.red,
      );
    } on TimeoutException {
      if (mounted) {
        _showFloatingSnackBar(
          AppLocalizations.of(context).errorTimeout ??
              'Request timed out. Please check your connection and try again.',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) {
        final message = NetworkUtils.isNetworkError(e)
            ? (AppLocalizations.of(context).errorNetwork ??
                'Network error. Please check your connection and try again.')
            : (AppLocalizations.of(context).errorGeneral ??
                'An error occurred. Please try again.');
        _showFloatingSnackBar(message, backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

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
                // Top bar with language selector
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button or empty space
                      const SizedBox(width: 40),
                      // Language selector
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(height: screenHeight * 0.02),

                              // Welcome header
                              _buildHeader(l10n, isDark),

                              SizedBox(height: screenHeight * 0.025),

                              // Verification message if needed
                              if (_showVerificationMessage) ...[
                                _buildVerificationBanner(l10n, isDark),
                                const SizedBox(height: 16),
                              ],

                              // Login form
                              _buildLoginForm(l10n, isDark),

                              const SizedBox(height: 20),

                              // Bottom links
                              _buildBottomLinks(l10n, isDark),

                              const SizedBox(height: 16),
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

  Widget _buildHeader(AppLocalizations l10n, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // App logo
        Image.asset(
          isDark
              ? 'assets/images/beyazlogo.png'
              : 'assets/images/siyahlogo.png',
          width: 80,
          height: 80,
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          l10n.welcomeBack ?? 'Welcome back',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationBanner(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.amber.withOpacity(0.15) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: Colors.amber.shade700,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.emailVerificationMessage ??
                      'Please verify your email to continue.',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    color:
                        isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _isResending ? null : _resendVerificationEmail,
              style: TextButton.styleFrom(
                backgroundColor: Colors.amber.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isResending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      l10n.resendVerificationEmail ??
                          'Resend Verification Email',
                      style: const TextStyle(
                        fontSize: 14,
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

  Widget _buildLoginForm(AppLocalizations l10n, bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Email field
          _buildInputLabel(l10n.emailLabel ?? 'Email', isDark),
          const SizedBox(height: 6),
          _buildEmailField(l10n, isDark),
          const SizedBox(height: 14),

          // Password field
          _buildInputLabel(l10n.passwordLabel ?? 'Password', isDark),
          const SizedBox(height: 6),
          _buildPasswordField(l10n, isDark),

          // Forgot Password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/forgot_password'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.forgotPasswordText ?? 'Forgot Password?',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Login button
          _buildLoginButton(l10n),

          const SizedBox(height: 16),

          // Divider
          _buildDivider(l10n, isDark),

          const SizedBox(height: 16),

          // Social sign-in buttons (Apple on iOS, Google on all platforms)
          _buildSocialButtons(l10n, isDark),
        ],
      ),
    );
  }

  Widget _buildSocialButtons(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        // Apple Sign In button - iOS only
        if (Platform.isIOS) ...[
          _buildAppleButton(l10n, isDark),
          const SizedBox(height: 12),
        ],
        // Google sign-in button - all platforms
        _buildGoogleButton(l10n, isDark),
      ],
    );
  }

  Widget _buildInputLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }

  Widget _buildEmailField(AppLocalizations l10n, bool isDark) {
    return TextFormField(
      controller: _emailController,
      focusNode: _emailFocusNode,
      keyboardType: TextInputType.emailAddress,
      cursorColor: isDark ? Colors.white : Colors.black87,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 16,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: l10n.emailHint ?? 'Enter your email',
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontFamily: 'Figtree',
        ),
        prefixIcon: Icon(
          Icons.email_outlined,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.orange.shade400,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1.5,
          ),
        ),
        errorStyle: const TextStyle(
          color: Colors.red,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.emailErrorEmpty ?? 'Email is required';
        }
        if (!InputValidator.isValidEmail(value)) {
          return l10n.emailErrorInvalid ?? 'Please enter a valid email';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField(AppLocalizations l10n, bool isDark) {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: !_isPasswordVisible,
      cursorColor: isDark ? Colors.white : Colors.black87,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 16,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: l10n.passwordHint ?? 'Enter your password',
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontFamily: 'Figtree',
        ),
        prefixIcon: Icon(
          Icons.lock_outline,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: isDark ? Colors.white38 : Colors.black38,
            size: 20,
          ),
          onPressed: () => setState(() {
            _isPasswordVisible = !_isPasswordVisible;
          }),
        ),
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.orange.shade400,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 1.5,
          ),
        ),
        errorStyle: const TextStyle(
          color: Colors.red,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return l10n.passwordErrorEmpty ?? 'Password is required';
        }
        final error = InputValidator.validatePassword(value);
        if (error != null) {
          return l10n.passwordErrorShort ?? error;
        }
        return null;
      },
    );
  }

  Widget _buildLoginButton(AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        onPressed: _isLoading ? null : _loginWithPassword,
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                l10n.loginButton ?? 'Sign In',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                ),
              ),
      ),
    );
  }

  Widget _buildDivider(AppLocalizations l10n, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.or ?? 'or',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontFamily: 'Figtree',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
      ],
    );
  }

  Widget _buildAppleButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleAppleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.apple,
              size: 24,
              color: isDark ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 12),
            Text(
              l10n.appleLoginButton ?? 'Continue with Apple',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                color: isDark ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          backgroundColor:
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          side: BorderSide(
            color: isDark ? Colors.white24 : Colors.grey.shade300,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/google_icon.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 12),
            Text(
              l10n.googleLoginButton ?? 'Continue with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLinks(AppLocalizations l10n, bool isDark) {
    return Column(
      children: [
        // Sign up link
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.dontHaveAccount ?? "Don't have an account? ",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontFamily: 'Figtree',
                fontSize: 14,
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/register'),
              child: Text(
                l10n.signUp ?? 'Sign Up',
                style: TextStyle(
                  color: Colors.orange.shade600,
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Guest continue
        TextButton(
          onPressed: () async {
            if (_twoFAPending) {
              await _authService.logout();
              setState(() => _twoFAPending = false);
            }
            context.go('/');
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.guestContinueText ?? 'Continue as Guest',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black45,
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward,
                color: isDark ? Colors.white38 : Colors.black45,
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
