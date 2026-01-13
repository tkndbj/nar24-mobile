import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/agreement_modal.dart';
import '../../auth_service.dart';
import '../../user_provider.dart';
import 'package:go_router/go_router.dart';
import '../AGREEMENTS/registration_agreement_screen.dart';
import '../AGREEMENTS/kullanim_kosullari.dart';
import '../AGREEMENTS/kisisel_veriler.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({Key? key}) : super(key: key);

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isAgreementAccepted = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

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
    _nameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeInController.dispose();
    super.dispose();
  }

  // Dismiss keyboard when tapping outside
  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  bool _hasMinLength(String password) => password.length >= 8;
  bool _hasUppercase(String password) => password.contains(RegExp(r'[A-Z]'));
  bool _hasLowercase(String password) => password.contains(RegExp(r'[a-z]'));
  bool _hasDigit(String password) => password.contains(RegExp(r'[0-9]'));
  bool _hasSpecialChar(String password) =>
      password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

  bool _isPasswordStrong(String password) {
    return _hasMinLength(password) &&
        _hasUppercase(password) &&
        _hasLowercase(password) &&
        _hasDigit(password) &&
        _hasSpecialChar(password);
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.red
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
        backgroundColor: backgroundColor ?? const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _register() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_isAgreementAccepted) {
      _showSnackBar(
        l10n.pleaseAcceptBothAgreements ??
            'Please accept both the membership agreement and terms of use to continue',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (!_isPasswordStrong(_passwordController.text)) {
      _showSnackBar(
        l10n.passwordDoesNotMeetRequirements ??
            'Password does not meet all requirements',
        backgroundColor: Colors.red,
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar(l10n.passwordsDoNotMatch, backgroundColor: Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = AuthService();
      final user = await authService.registerWithEmailAndPassword(
        _emailController.text,
        _passwordController.text,
        _nameController.text,
        _surnameController.text,
      );

      context.go('/email-verification');
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? l10n.error, backgroundColor: Colors.red);
    } catch (e) {
      _showSnackBar(e.toString(), backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final result = await AuthService().signInWithGoogle();
      final User? user = result['user'];

      if (user != null) {
        // Update UserProvider with profile completion status
        // Profile completion is now optional - navigate directly to home
        if (!mounted) return;
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final bool needsComplete = result['needsCompletion'] ?? true;
        await userProvider.updateUserDataImmediately(user,
            profileComplete: !needsComplete);

        if (!mounted) return;

        // Show agreement modal for Google users who haven't accepted yet
        final hasAccepted =
            await AgreementModal.hasAcceptedAgreements(user.uid);
        if (!hasAccepted && mounted) {
          await AgreementModal.show(context);
        }

        if (!mounted) return;
        // Navigate directly to home - profile completion is optional
        context.go('/');
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message =
              'An account already exists with this email using a different sign-in method.';
          break;
        case 'network-error':
          message =
              'Network error. Please check your connection and try again.';
          break;
        default:
          message = e.message ??
              AppLocalizations.of(context).errorGeneral ??
              'Google registration failed. Please try again.';
      }

      if (mounted) {
        _showSnackBar(
            '${AppLocalizations.of(context).registerWithGoogle}: $message',
            backgroundColor: Colors.red);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
            AppLocalizations.of(context).errorGeneral ??
                'An error occurred. Please try again.',
            backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerWithApple() async {
    setState(() => _isLoading = true);
    try {
      final result = await AuthService().signInWithApple();
      final User? user = result['user'];
      final bool needsComplete = result['needsCompletion'] ?? true;
      final bool needsName = result['needsName'] ?? false;

      if (user != null) {
        if (!mounted) return;
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        await userProvider.updateUserDataImmediately(user,
            profileComplete: !needsComplete);

        // ✅ FIX: Set name completion state so router knows to redirect
        // REMOVED: Manual navigation to /complete-name
        // The router will handle the redirect automatically
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
        context.go('/');
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message =
              'An account already exists with this email using a different sign-in method.';
          break;
        case 'network-error':
          message =
              'Network error. Please check your connection and try again.';
          break;
        default:
          message = e.message ??
              AppLocalizations.of(context).errorGeneral ??
              'Apple registration failed. Please try again.';
      }

      if (mounted) {
        _showSnackBar(
            '${AppLocalizations.of(context).registerWithApple ?? "Register with Apple"}: $message',
            backgroundColor: Colors.red);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
            AppLocalizations.of(context).errorGeneral ??
                'An error occurred. Please try again.',
            backgroundColor: Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),

                                // Header
                                _buildHeader(l10n, isDark),

                                const SizedBox(height: 24),

                                // Name fields row
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _nameController,
                                        label: l10n.name,
                                        hint: l10n.name,
                                        icon: Icons.person_outline,
                                        isDark: isDark,
                                        l10n: l10n,
                                        textCapitalization:
                                            TextCapitalization.words,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildTextField(
                                        controller: _surnameController,
                                        label: l10n.surname,
                                        hint: l10n.surname,
                                        icon: Icons.person_outline,
                                        isDark: isDark,
                                        l10n: l10n,
                                        textCapitalization:
                                            TextCapitalization.words,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Email
                                _buildTextField(
                                  controller: _emailController,
                                  label: l10n.email,
                                  hint: l10n.enterEmail,
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  isDark: isDark,
                                  l10n: l10n,
                                  isEmail: true,
                                ),
                                const SizedBox(height: 12),

                                // Password
                                _buildTextField(
                                  controller: _passwordController,
                                  label: l10n.password,
                                  hint: l10n.enterPassword,
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  isPasswordVisible: _isPasswordVisible,
                                  onTogglePassword: () => setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  }),
                                  isDark: isDark,
                                  l10n: l10n,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 12),

                                // Confirm Password
                                _buildTextField(
                                  controller: _confirmPasswordController,
                                  label: l10n.confirmPassword,
                                  hint: l10n.confirmPassword,
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  isPasswordVisible: _isConfirmPasswordVisible,
                                  onTogglePassword: () => setState(() {
                                    _isConfirmPasswordVisible =
                                        !_isConfirmPasswordVisible;
                                  }),
                                  isDark: isDark,
                                  l10n: l10n,
                                ),

                                // Password strength indicator
                                if (_passwordController.text.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildPasswordStrengthIndicator(l10n, isDark),
                                ],

                                const SizedBox(height: 16),

                                // Agreement checkbox
                                _buildAgreementCheckbox(l10n, isDark),
                                const SizedBox(height: 20),

                                // Register button
                                _buildRegisterButton(l10n),
                                const SizedBox(height: 20),

                                // Divider
                                _buildDivider(l10n, isDark),
                                const SizedBox(height: 20),

                                // Social sign-in buttons (Apple on iOS, Google on all platforms)
                                _buildSocialButtons(l10n, isDark),
                                const SizedBox(height: 20),

                                // Already have account
                                _buildLoginLink(l10n, isDark),
                                const SizedBox(height: 24),
                              ],
                            ),
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
            onTap: () => Navigator.of(context).pop(),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00A86B), Color(0xFF00C853)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.person_add_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.createAccount,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'Figtree',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.joinUsToday ?? 'Join us today!',
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'Figtree',
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    required AppLocalizations l10n,
    bool isPassword = false,
    bool? isPasswordVisible,
    VoidCallback? onTogglePassword,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    bool isEmail = false,
    bool isOptional = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !(isPasswordVisible ?? false),
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: TextStyle(
        fontFamily: 'Figtree',
        fontSize: 15,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark ? Colors.white60 : Colors.black54,
          fontFamily: 'Figtree',
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white30 : Colors.black26,
          fontFamily: 'Figtree',
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          color: isDark ? Colors.white38 : Colors.black38,
          size: 20,
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isPasswordVisible ?? false
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 20,
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor:
            isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
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
      validator: isOptional
          ? null
          : (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.requiredField(label.split(' (')[0]);
              }
              if (isEmail &&
                  !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                return l10n.invalidEmail;
              }
              if (isPassword && value.trim().length < 6) {
                return l10n.passwordTooShort;
              }
              return null;
            },
    );
  }

  Widget _buildPasswordStrengthIndicator(AppLocalizations l10n, bool isDark) {
    final password = _passwordController.text;
    final criteria = [
      (
        met: _hasMinLength(password),
        text: l10n.passwordMinLength ?? 'At least 8 characters'
      ),
      (
        met: _hasUppercase(password),
        text: l10n.passwordUppercase ?? 'One uppercase letter'
      ),
      (
        met: _hasLowercase(password),
        text: l10n.passwordLowercase ?? 'One lowercase letter'
      ),
      (met: _hasDigit(password), text: l10n.passwordDigit ?? 'One number'),
      (
        met: _hasSpecialChar(password),
        text: l10n.passwordSpecialChar ?? 'One special character'
      ),
    ];

    final metCount = criteria.where((c) => c.met).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: metCount / 5,
                    backgroundColor:
                        isDark ? Colors.white12 : Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      metCount < 3
                          ? Colors.red
                          : metCount < 5
                              ? Colors.orange
                              : const Color(0xFF00A86B),
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$metCount/5',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Figtree',
                  fontWeight: FontWeight.w600,
                  color: metCount == 5
                      ? const Color(0xFF00A86B)
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Criteria grid (2 columns for compactness)
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: criteria
                .map((c) => _buildCriteriaChip(c.met, c.text, isDark))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaChip(bool isMet, String text, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: isMet
              ? const Color(0xFF00A86B)
              : (isDark ? Colors.white30 : Colors.black26),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Figtree',
            color: isMet
                ? const Color(0xFF00A86B)
                : (isDark ? Colors.white54 : Colors.black45),
            fontWeight: isMet ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildAgreementCheckbox(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isAgreementAccepted
              ? const Color(0xFF00A86B).withOpacity(0.5)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: _isAgreementAccepted,
              onChanged: (value) {
                setState(() => _isAgreementAccepted = value ?? false);
              },
              activeColor: const Color(0xFF00A86B),
              checkColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              children: [
                Text(
                  l10n.iAgreeToThe ?? 'I agree to the ',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Figtree',
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegistrationAgreementScreen(),
                    ),
                  ),
                  child: Text(
                    l10n.membershipAgreement ?? 'Membership Agreement',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'Figtree',
                      color: Color(0xFF00A86B),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  ' ${l10n.andText ?? "and"} ',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Figtree',
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsOfUseScreen(),
                    ),
                  ),
                  child: Text(
                    l10n.termsOfUse ?? 'Terms of Use',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'Figtree',
                      color: Color(0xFF00A86B),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  ' ${l10n.andText ?? "and"} ',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Figtree',
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PersonalDataScreen(),
                    ),
                  ),
                  child: Text(
                    l10n.personalData ?? 'Personal Data',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'Figtree',
                      color: Color(0xFF00A86B),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterButton(AppLocalizations l10n) {
    return SizedBox(
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
        onPressed: _isLoading ? null : _register,
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
                l10n.register,
                style: const TextStyle(
                  fontSize: 15,
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
              fontSize: 13,
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

  Widget _buildAppleButton(AppLocalizations l10n, bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _registerWithApple,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
            const SizedBox(width: 10),
            Text(
              l10n.registerWithApple ?? 'Register with Apple',
              style: TextStyle(
                fontSize: 14,
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
        onPressed: _isLoading ? null : _registerWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor:
              isDark ? Colors.white.withOpacity(0.04) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          side: BorderSide(
            color: isDark ? Colors.white30 : Colors.grey.shade300,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
            const SizedBox(width: 10),
            Text(
              l10n.registerWithGoogle,
              style: TextStyle(
                fontSize: 14,
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

  Widget _buildLoginLink(AppLocalizations l10n, bool isDark) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.alreadyHaveAccount.split('?')[0] ??
                'Already have an account? ',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontFamily: 'Figtree',
              fontSize: 14,
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/login'),
            child: Text(
              l10n.loginButton ?? 'Sign In',
              style: const TextStyle(
                color: Color(0xFF00A86B),
                fontFamily: 'Figtree',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
