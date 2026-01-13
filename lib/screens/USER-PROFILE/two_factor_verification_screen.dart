// lib/screens/two_factor_verification_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import '../../services/two_factor_service.dart';
import '../../generated/l10n/app_localizations.dart';

class TwoFactorVerificationScreen extends StatefulWidget {
  final String type; // 'setup', 'login', 'disable'

  const TwoFactorVerificationScreen({
    Key? key,
    required this.type,
  }) : super(key: key);

  @override
  State<TwoFactorVerificationScreen> createState() =>
      _TwoFactorVerificationScreenState();
}

class _TwoFactorVerificationScreenState
    extends State<TwoFactorVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final TwoFactorService _twoFactorService = TwoFactorService();

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  Timer? _timer;
  int _secondsRemaining = 0;

  // TOTP setup içeriği
  String? _otpauth;
  String? _secretBase32;

  @override
  void initState() {
    super.initState();
    _initFlow();
    // Removed the hidden field listener since we're using a simpler approach
  }

  Future<void> _initFlow() async {
    // Akışa göre başlat
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> res;
      if (widget.type == 'setup') {
        res = await _twoFactorService.start2FASetup();
        if (res['success'] == true && res['method'] == 'totp') {
          _otpauth = res['otpauth'] as String?;
          _secretBase32 = res['secretBase32'] as String?;
        } else if (res['success'] == true && res['method'] == 'email') {
          _startResendTimer();
        }
      } else if (widget.type == 'login') {
        res = await _twoFactorService.start2FALogin();
      } else if (widget.type == 'disable') {
        res = await _twoFactorService.start2FADisable();
        if (res['success'] == true && res['method'] == 'email') {
          _startResendTimer();
        }
      }
    } catch (_) {
      // görsel hata metni
      _errorMessage = AppLocalizations.of(context).twoFactorInitError;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // Focus first field after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_focusNodes[0].canRequestFocus) {
            _focusNodes[0].requestFocus();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Removed hidden controller cleanup since we're using a simpler approach
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _secondsRemaining = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          t.cancel();
        }
      });
    });
  }

  String _getCode() => _controllers.map((c) => c.text).join();

  void _onCodeChanged(int index, String value) {
    // Handle paste - if value has multiple characters
    if (value.length > 1) {
      final cleanValue = value.replaceAll(RegExp(r'[^0-9]'), '');
      print('Pasted value: "$value", clean: "$cleanValue"'); // Debug

      if (cleanValue.length >= 6) {
        // Fill all fields with pasted content
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = cleanValue[i];
        }
        setState(() => _errorMessage = null);
        _focusNodes[5].requestFocus();
        Future.delayed(const Duration(milliseconds: 200), () {
          _verifyCode();
        });
        return;
      } else if (cleanValue.isNotEmpty) {
        // Single digit from multi-character paste
        _controllers[index].text = cleanValue[0];
        value = cleanValue[0];
      } else {
        // No valid digits
        _controllers[index].clear();
        return;
      }
    }

    // Normal single character input
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (index == 5 && value.isNotEmpty) {
      _verifyCode();
    }
    setState(() => _errorMessage = null);
  }

  void _onCodeDeleted(int index, String value) {
    if (value.isEmpty && index > 0) {
      // Move to previous field and clear it
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _switchToEmailFallback() async {
    final l10n = AppLocalizations.of(context);
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Pass the current type to useEmailFallback
      // This ensures 'setup' gets normalized to 'enable' for the backend
      final res = await _twoFactorService.useEmailFallback(widget.type);

      if (res['success'] == true) {
        _clearCode();
        _startResendTimer();

        if (!mounted) return;

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.twoFactorEmailCodeSent ??
                  'Verification code sent to your email',
            ),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Force UI rebuild to show email input mode
        setState(() {
          // The UI will now show email-related elements since _currentMethod is 'email'
        });
      } else {
        setState(() {
          // Properly resolve the error message
          final messageKey = res['message'] as String? ?? 'twoFactorInitError';
          _errorMessage = _resolveMessage(l10n, messageKey);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            l10n.twoFactorInitError ?? 'Failed to send email verification';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _resolveMessage(AppLocalizations l10n, String key) {
    switch (key) {
      case 'emailCodeSent':
        return l10n.twoFactorEmailCodeSent ??
            'Verification code sent to your email';
      case 'twoFactorInitError':
        return l10n.twoFactorInitError ?? 'Failed to initialize verification';
      case 'pleasewait30seconds':
        return l10n.twoFactorPleaseWait ??
            'Please wait 30 seconds before requesting a new code';
      case 'twoFactorEnabledSuccess':
        return l10n.twoFactorEnabledSuccess ??
            'Two-factor authentication enabled successfully';
      case 'twoFactorDisabledSuccess':
        return l10n.twoFactorDisabledSuccess ??
            'Two-factor authentication disabled successfully';
      case 'verificationSuccess':
        return l10n.twoFactorVerificationSuccess ?? 'Verification successful';
      case 'codeNotFound':
        return l10n.twoFactorCodeNotFound ?? 'Verification code not found';
      case 'codeExpired':
        return l10n.twoFactorCodeExpired ?? 'Verification code has expired';
      case 'tooManyAttempts':
        return l10n.twoFactorTooManyAttempts ??
            'Too many attempts. Please try again later';
      case 'enterAuthenticatorCode':
        return l10n.twoFactorEnterAuthenticatorCode ??
            'Enter code from your authenticator app';
      case 'enterAuthenticatorCodeToDisable':
        return l10n.twoFactorEnterAuthenticatorCodeToDisable ??
            'Enter code to disable 2FA';
      case 'resendNotApplicableForTotp':
        return l10n.twoFactorResendNotApplicableForTotp ??
            'Cannot resend code for authenticator app';
      default:
        return key; // Return the key itself if no translation found
    }
  }

  Future<void> _verifyCode() async {
    final l10n = AppLocalizations.of(context);
    final code = _getCode();
    if (code.length != 6) {
      setState(() => _errorMessage = l10n.twoFactorCodeIncomplete);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> result;
      switch (widget.type) {
        case 'setup':
          result = await _twoFactorService.verify2FASetup(code);
          break;
        case 'login':
          result = await _twoFactorService.verify2FALogin(code);
          break;
        case 'disable':
          result = await _twoFactorService.verify2FADisable(code);
          break;
        default:
          throw Exception('Invalid verification type');
      }

      if (result['success'] == true) {
        if (!mounted) return;

        // ✅ FIX: Determine success message by widget.type, not from backend
        final successMessage = switch (widget.type) {
          'setup' => l10n.twoFactorEnabledSuccess,
          'disable' => l10n.twoFactorDisabledSuccess,
          _ => l10n.twoFactorVerificationSuccess, // login case
        };

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.pop(true);
      } else {
        setState(() {
          _errorMessage = l10n.resolve(
              result['message'] as String? ?? 'twoFactorVerificationError',
              args: result['remaining'] != null
                  ? [result['remaining'].toString()]
                  : null);
        });
        _clearCode();
      }
    } catch (_) {
      setState(() {
        _errorMessage = l10n.twoFactorVerificationError;
      });
      _clearCode();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    if (_focusNodes[0].canRequestFocus) {
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendCode() async {
    final l10n = AppLocalizations.of(context);
    if (_isResending || _secondsRemaining > 0) return;
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    try {
      final res = await _twoFactorService.resendVerificationCode();
      if (res['success'] == true) {
        _startResendTimer();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n.resolve(res['message'] as String? ?? 'emailCodeSent')),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              l10n.resolve(res['message'] as String? ?? 'twoFactorResendError');
        });
      }
    } catch (_) {
      setState(() => _errorMessage = l10n.twoFactorResendError);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String _getTitle() {
    final l10n = AppLocalizations.of(context);
    switch (widget.type) {
      case 'setup':
        return l10n.twoFactorSetupTitle;
      case 'login':
        return l10n.twoFactorLoginTitle;
      case 'disable':
        return l10n.twoFactorDisableTitle;
      default:
        return l10n.twoFactorVerificationTitle;
    }
  }

  String _getSubtitle() {
    final l10n = AppLocalizations.of(context);
    switch (widget.type) {
      case 'setup':
        return l10n.twoFactorSetupSubtitle;
      case 'login':
        return l10n.twoFactorLoginSubtitle;
      case 'disable':
        return l10n.twoFactorDisableSubtitle;
      default:
        return l10n.twoFactorVerificationSubtitle;
    }
  }

  Future<void> _openAuthenticator() async {
    final l10n = AppLocalizations.of(context);
    final uri = _otpauth;
    if (uri == null || uri.isEmpty) return;
    final ok =
        await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.twoFactorOpenAuthenticatorFailed),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copySecret() async {
    final l10n = AppLocalizations.of(context);
    final s = _secretBase32 ?? '';
    if (s.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: s));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.copied),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final method = _twoFactorService.currentMethod; // 'totp' | 'email' | null

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(FeatherIcons.arrowLeft,
                color: theme.textTheme.bodyMedium?.color),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _getTitle(),
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.pink],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Icon(
                            widget.type == 'disable'
                                ? FeatherIcons.shieldOff
                                : FeatherIcons.shield,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),

                        const SizedBox(height: 24),

                        Text(
                          _getTitle(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getSubtitle(),
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 24),

                        // SADECE login + TOTP iken göster - CENTERED
                        if (widget.type == 'login' && method == 'totp')
                          Center(
                            child: TextButton.icon(
                              onPressed:
                                  _isLoading ? null : _switchToEmailFallback,
                              icon: const Icon(FeatherIcons.mail, size: 16),
                              label: Text(
                                l10n.twoFactorUseEmailInstead ??
                                    'E-posta ile doğrula (yedek)',
                              ),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.orange),
                            ),
                          ),

                        const SizedBox(height: 12),

                        // ───────────── TOTP Setup üçlü seçenek ─────────────
                        if (widget.type == 'setup' && method == 'totp') ...[
                          // 1) Authenticator'a ekle (deep-link)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _openAuthenticator,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.link, color: Colors.white),
                              label: Text(
                                l10n.twoFactorAddToAuthenticatorButton,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2) QR ile kur
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  l10n.twoFactorQrSubtitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                if (_otpauth != null && _otpauth!.isNotEmpty)
                                  QrImageView(
                                    data: _otpauth!,
                                    version: QrVersions.auto,
                                    size: 180,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3) Manuel kurulum anahtarı
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.twoFactorManualSetupTitle,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.twoFactorManualSetupHint,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: theme.scaffoldBackgroundColor,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color:
                                                  Colors.grey.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          _secretBase32 ?? '',
                                          style: const TextStyle(
                                            letterSpacing: 1.2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: _copySecret,
                                      icon: const Icon(FeatherIcons.copy),
                                      tooltip: l10n.copy,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                          Text(
                            l10n.twoFactorEnter6DigitsBelow,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // 6 haneli kod girişi (tüm akışlar için) - improved with better paste and delete
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 45,
                              height: 55,
                              child: TextFormField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  // Remove the length limiting to allow paste
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.cardColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: _errorMessage != null
                                          ? Colors.red
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: _errorMessage != null
                                          ? Colors.red
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: _errorMessage != null
                                          ? Colors.red
                                          : Colors.orange,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onChanged: (value) =>
                                    _onCodeChanged(index, value),
                                onTap: () {
                                  if (_controllers[index].text.isNotEmpty) {
                                    _controllers[index].selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset:
                                              _controllers[index].text.length),
                                    );
                                  }
                                },
                              ),
                            );
                          }),
                        ),

                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(FeatherIcons.alertCircle,
                                    color: Colors.red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              disabledBackgroundColor:
                                  Colors.grey.withOpacity(0.3),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white)),
                                  )
                                : Text(
                                    l10n.twoFactorVerifyButton,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Resend bölümü: sadece e-posta metodunda
                if (method == 'email')
                  Column(
                    children: [
                      if (_secondsRemaining > 0)
                        Text(
                          '${l10n.twoFactorResendIn} $_secondsRemaining ${l10n.seconds}',
                          style: TextStyle(
                            color: theme.textTheme.bodyMedium?.color
                                ?.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: _isResending ? null : _resendCode,
                          icon: _isResending
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.orange.withOpacity(0.7)),
                                  ),
                                )
                              : const Icon(FeatherIcons.refreshCw, size: 16),
                          label: Text(l10n.twoFactorResendCode),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.orange),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.twoFactorEmailFallback,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color
                              ?.withOpacity(0.6),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Küçük yardımcı: AppLocalizations için dinamik key çözümleme
extension _L10nResolve on AppLocalizations {
  String resolve(String key, {List<String>? args}) {
    // Bu basit resolver, anahtarları ARB'ye ekleyince düzgün çalışır.
    switch (key) {
      case 'emailCodeSent':
        return twoFactorEmailCodeSent; // yeni l10n anahtarı
      case 'twoFactorEnabledSuccess':
        return twoFactorEnabledSuccess;
      case 'twoFactorDisabledSuccess':
        return twoFactorDisabledSuccess;
      case 'verificationSuccess':
        return twoFactorVerificationSuccess;
      case 'codeNotFound':
        return twoFactorCodeNotFound;
      case 'codeExpired':
        return twoFactorCodeExpired;
      case 'tooManyAttempts':
        return twoFactorTooManyAttempts;
      case 'invalidCodeWithRemaining':
        final remaining = (args != null && args.isNotEmpty) ? args.first : '0';
        return twoFactorInvalidCodeWithRemaining(remaining);
      case 'enterAuthenticatorCode':
        return twoFactorEnterAuthenticatorCode;
      case 'enterAuthenticatorCodeToDisable':
        return twoFactorEnterAuthenticatorCodeToDisable;
      case 'resendNotApplicableForTotp':
        return twoFactorResendNotApplicableForTotp;
      default:
        return twoFactorVerificationError;
    }
  }
}
