// lib/screens/ads/isbank_ads_images_payment_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

import '../../generated/l10n/app_localizations.dart';

// =============================================================================
// ENTRY POINT
// =============================================================================

class IsbankAdsImagesPaymentScreen extends StatefulWidget {
  final String submissionId;
  final String paymentLink;
  final double price;
  final String shopId;
  final String shopName;

  const IsbankAdsImagesPaymentScreen({
    super.key,
    required this.submissionId,
    required this.paymentLink,
    required this.price,
    required this.shopId,
    required this.shopName,
  });

  @override
  State<IsbankAdsImagesPaymentScreen> createState() =>
      _IsbankAdsImagesPaymentScreenState();
}

// =============================================================================
// STATE
// =============================================================================

enum _PaymentStatus { initializing, initError, pending, completed, failed, timeout }

class _IsbankAdsImagesPaymentScreenState
    extends State<IsbankAdsImagesPaymentScreen> {
  // Initialization
  String? _gatewayUrl;
  Map<String, String>? _paymentParams;
  String? _orderNumber;
  String? _initError;

  // WebView
  InAppWebViewController? _webController;
  bool _initialLoadDone = false;

  // Payment state
  _PaymentStatus _status = _PaymentStatus.initializing;
  String? _failureMessage;

  // Guard against double-handling
  bool _resultHandled = false;

  // Realtime listener + fallback poll timer
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _firestoreListener;
  Timer? _fallbackTimer;
  int _fallbackPollCount = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializePayment();
  }

  @override
  void dispose() {
    _firestoreListener?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  // =============================================================================
  // INITIALIZATION — calls Cloud Function to get gateway URL + params
  // =============================================================================

  Future<void> _initializePayment() async {
    setState(() {
      _status    = _PaymentStatus.initializing;
      _initError = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('initializeIsbankAdPayment');

      final result = await callable.call({
        'submissionId': widget.submissionId,
        'paymentLink':  widget.paymentLink,
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        throw Exception('Payment initialization failed');
      }

      // Cast paymentParams values to String — the form requires String values
      final rawParams = Map<String, dynamic>.from(data['paymentParams'] as Map);

      if (!mounted) return;
      setState(() {
        _gatewayUrl    = data['gatewayUrl'] as String;
        _paymentParams = rawParams.map((k, v) => MapEntry(k, v.toString()));
        _orderNumber   = data['orderNumber'] as String;
        _status        = _PaymentStatus.pending;
      });

      _startFirestoreListener();
      _startFallbackPolling();
    } catch (e) {
      debugPrint('[AdPayment] Initialization error: $e');
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _status    = _PaymentStatus.initError;
      });
    }
  }

  // =============================================================================
  // REALTIME FIRESTORE LISTENER (primary mechanism)
  // =============================================================================

  void _startFirestoreListener() {
    _firestoreListener = FirebaseFirestore.instance
        .collection('pendingAdPayments')
        .doc(_orderNumber)
        .snapshots()
        .listen(
      (snap) {
        if (!snap.exists || _resultHandled || !mounted) return;
        final data   = snap.data()!;
        final status = data['status'] as String?;

        switch (status) {
          case 'completed':
            _handlePaymentSuccess();
            break;
          case 'payment_failed':
          case 'hash_verification_failed':
            _handlePaymentFailed((data['errorMessage'] as String?) ?? '');
            break;
          case 'payment_succeeded_activation_failed':
            _handlePaymentFailed(
              AppLocalizations.of(context).paymentReceivedActivationFailed,
            );
            break;
        }
      },
      onError: (Object e) {
        debugPrint('[AdPayment] Firestore listener error: $e');
      },
    );
  }

  // =============================================================================
  // FALLBACK POLLING (safety net if Firestore listener drops)
  // =============================================================================
  //
  //   • First 10 polls: every 5s  (0–50s)
  //   • Next  20 polls: every 10s (50s–250s ≈ 4 min)
  //   Total: 30 polls before timeout.

  void _startFallbackPolling() {
    _fallbackTimer?.cancel();
    _fallbackPollCount = 0;
    _scheduleFallbackPoll();
  }

  void _scheduleFallbackPoll() {
    if (!mounted || _resultHandled) return;

    final delay = _fallbackPollCount < 10
        ? const Duration(seconds: 5)
        : const Duration(seconds: 10);

    _fallbackTimer = Timer(delay, () async {
      if (!mounted || _resultHandled) return;
      _fallbackPollCount++;

      if (_fallbackPollCount > 30) {
        if (mounted && !_resultHandled) {
          setState(() {
            _status         = _PaymentStatus.timeout;
            _failureMessage = AppLocalizations.of(context).paymentTimedOutRetry;
          });
        }
        return;
      }

      try {
        final snap = await FirebaseFirestore.instance
            .collection('pendingAdPayments')
            .doc(_orderNumber)
            .get();

        if (!snap.exists || _resultHandled || !mounted) return;
        final status = snap.data()?['status'] as String?;

        if (status == 'completed') {
          _handlePaymentSuccess();
          return;
        } else if (status == 'payment_failed' ||
            status == 'hash_verification_failed') {
          _handlePaymentFailed(
            (snap.data()?['errorMessage'] as String?) ?? '',
          );
          return;
        }
      } catch (e) {
        debugPrint('[AdPayment] Fallback poll error: $e');
      }

      if (!_resultHandled && mounted && _status == _PaymentStatus.pending) {
        _scheduleFallbackPoll();
      }
    });
  }

  // =============================================================================
  // DEEP LINK INTERCEPTION
  // =============================================================================

  Future<NavigationActionPolicy> _onShouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';

    if (url.startsWith('ad-payment-success://')) {
      _handlePaymentSuccess();
      return NavigationActionPolicy.CANCEL;
    }

    if (url.startsWith('ad-payment-failed://')) {
      final message = Uri.decodeComponent(
        url.replaceFirst('ad-payment-failed://', ''),
      );
      _handlePaymentFailed(message);
      return NavigationActionPolicy.CANCEL;
    }

    if (url.startsWith('ad-payment-status://')) {
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  // =============================================================================
  // RESULT HANDLERS
  // =============================================================================

void _handlePaymentSuccess() {
  if (_resultHandled) return;
  _resultHandled = true;

  _fallbackTimer?.cancel();
  _firestoreListener?.cancel();

  if (!mounted) return;
  setState(() => _status = _PaymentStatus.completed);

  Future.delayed(const Duration(milliseconds: 500), () {
    if (!mounted) return;
    context.go(
      '/seller-panel/ads_screen',
      extra: {
        'shopId': widget.shopId,
        'shopName': widget.shopName,
        'initialTabIndex': 1,      // land on "My Ads" tab
      },
    );
  });
}

  void _handlePaymentFailed(String message) {
    if (_resultHandled) return;
    _resultHandled = true;

    _fallbackTimer?.cancel();
    _firestoreListener?.cancel();

    if (!mounted) return;
    setState(() {
      _status         = _PaymentStatus.failed;
      _failureMessage = message.trim().isEmpty
          ? AppLocalizations.of(context).paymentFailedDefault
          : message;
    });
  }

  // =============================================================================
  // POST FORM SUBMISSION
  // =============================================================================

  void _submitPostForm(InAppWebViewController controller) {
    final encoded = _paymentParams!.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    controller.postUrl(
      url: WebUri(_gatewayUrl!),
      postData: Uint8List.fromList(utf8.encode(encoded)),
    );
  }

  // =============================================================================
  // CANCEL HANDLER
  // =============================================================================

  Future<void> _handleCancel() async {
    if (_status == _PaymentStatus.completed || _resultHandled) return;

    if (_status == _PaymentStatus.failed || _status == _PaymentStatus.timeout) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }

    _fallbackTimer?.cancel();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _CancelDialog(isDark: _isDark),
    );

    if (!mounted) return;

    if (confirmed == true) {
      Navigator.of(context).pop(false);
    } else {
      if (!_resultHandled) _startFallbackPolling();
    }
  }

  // =============================================================================
  // HELPERS
  // =============================================================================

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final l10n   = AppLocalizations.of(context);

    // ── Initializing ─────────────────────────────────────────────────────────
    if (_status == _PaymentStatus.initializing) {
      return _Scaffold(
        isDark: isDark,
        onCancel: null, // disabled during init
        child: _InitializingView(isDark: isDark, l10n: l10n),
      );
    }

    // ── Init error ────────────────────────────────────────────────────────────
    if (_status == _PaymentStatus.initError) {
      return _Scaffold(
        isDark: isDark,
        onCancel: () => Navigator.of(context).pop(false),
        child: _ErrorView(
          isDark: isDark,
          l10n: l10n,
          message: _initError ?? l10n.paymentProcessingError,
          onRetry: _initializePayment,
        ),
      );
    }

    // ── Success screen ────────────────────────────────────────────────────────
    if (_status == _PaymentStatus.completed) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.check_circle_rounded,
        iconColor: const Color(0xFF38A169),
        iconBgColor: const Color(0xFF38A169).withOpacity(0.15),
        title: l10n.paymentSuccessful,
        subtitle: l10n.adPaymentSuccessMessage,
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: const Color(0xFF38A169),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.redirecting,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF38A169),
              ),
            ),
          ],
        ),
      );
    }

    // ── Failed / Timeout screen ───────────────────────────────────────────────
    if (_status == _PaymentStatus.failed || _status == _PaymentStatus.timeout) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: _status == _PaymentStatus.timeout
            ? l10n.paymentTimedOutTitle
            : l10n.paymentFailedTitle,
        subtitle: _failureMessage ?? l10n.paymentProcessingError,
        actions: [
          _PrimaryButton(
            label: l10n.tryAgain,
            onTap: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
          ),
        ],
      );
    }

    // ── Active payment WebView ────────────────────────────────────────────────
    return _Scaffold(
      isDark: isDark,
      onCancel: _handleCancel,
      child: Stack(
        children: [
          // WebView container
          Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.grey[700]!.withOpacity(0.5)
                    : Colors.grey[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InAppWebView(
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  mediaPlaybackRequiresUserGesture: false,
                  transparentBackground: false,
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                  _submitPostForm(controller);
                },
                onLoadStop: (controller, url) {
                  if (!_initialLoadDone && mounted) {
                    setState(() => _initialLoadDone = true);
                  }
                },
                onReceivedError: (controller, request, error) {
                  debugPrint('[AdPayment] WebView error: ${error.description}');
                  if (!_initialLoadDone && mounted) {
                    setState(() => _initialLoadDone = true);
                  }
                },
                shouldOverrideUrlLoading: _onShouldOverrideUrlLoading,
              ),
            ),
          ),

          // Loading overlay
          if (!_initialLoadDone)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            color: const Color(0xFF667EEA).withOpacity(0.5),
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            color: Color(0xFF667EEA),
                            strokeWidth: 3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.loadingPaymentPage,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.pleaseWait,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[300],
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

 }

// =============================================================================
// SCAFFOLD WRAPPER
// Keeps the AppBar consistent across all sub-states.
// =============================================================================

class _Scaffold extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onCancel;
  final Widget child;

  const _Scaffold({
    required this.isDark,
    required this.onCancel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1B23) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          onPressed: onCancel,
        ),
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(
              l10n.securePayment,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1A202C),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}

// =============================================================================
// INITIALIZING VIEW
// =============================================================================

class _InitializingView extends StatelessWidget {
  final bool isDark;
  final AppLocalizations l10n;

  const _InitializingView({required this.isDark, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.initializingPayment,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ERROR VIEW (initialization failure with retry)
// =============================================================================

class _ErrorView extends StatelessWidget {
  final bool isDark;
  final AppLocalizations l10n;
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.isDark,
    required this.l10n,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 24),
            Text(
              l10n.connectionError,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A202C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// FULL SCREEN MESSAGE (success / failure / timeout)
// =============================================================================

class _FullScreenMessage extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final String title;
  final String subtitle;
  final Widget? footer;
  final List<Widget> actions;

  const _FullScreenMessage({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.iconBgColor,
    this.footer,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: iconBgColor ?? iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: iconColor),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A202C),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: 16),
                footer!,
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                ...actions,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PRIMARY BUTTON
// =============================================================================

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}

// =============================================================================
// CANCEL DIALOG
// =============================================================================

class _CancelDialog extends StatelessWidget {
  final bool isDark;

  const _CancelDialog({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        l10n.cancelPaymentTitle,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF1A202C),
        ),
      ),
      content: Text(
        l10n.cancelPaymentMessage,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.no,
            style: TextStyle(
              color: isDark ? Colors.grey[300] : const Color(0xFF64748B),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          child: Text(
            l10n.yes,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}