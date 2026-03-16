// lib/screens/market/isbank_payment_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../generated/l10n/app_localizations.dart';
import '../../providers/cart_provider.dart';

// =============================================================================
// ENTRY POINT
// =============================================================================

class IsbankPaymentScreen extends StatefulWidget {
  final String gatewayUrl;
  final String orderNumber;
  final Map<String, String> paymentParams;

  const IsbankPaymentScreen({
    super.key,
    required this.gatewayUrl,
    required this.orderNumber,
    required this.paymentParams,
  });

  @override
  State<IsbankPaymentScreen> createState() => _IsbankPaymentScreenState();
}

// =============================================================================
// STATE
// =============================================================================

// Only two terminal states on this screen.
// Success and processing both navigate away to the orders screen immediately.
enum _PaymentStatus { pending, failed }

class _IsbankPaymentScreenState extends State<IsbankPaymentScreen> {
  // WebView
  InAppWebViewController? _webController;
  bool _initialLoadDone = false;

  // Payment state
  _PaymentStatus _paymentStatus = _PaymentStatus.pending;
  String? _error;

  // Brief success overlay shown before navigating away — gives visual feedback
  // and lets the framework dispose the WebView before the new route builds.
  bool _isNavigatingAway = false;

  // Guard against double-handling across all three signal sources
  // (deep link, Firestore fast-path, WebView timeout)
  bool _resultHandled = false;

  // Fast-path listener: catches the rare case where the server processes
  // the callback and writes 'completed' before the bank even redirects
  // the WebView (e.g. very fast 3DS auth + no network latency).
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _firestoreListener;

  // Hard timeout for the WebView loading phase only.
  // If the bank page never loads in 60s, something is wrong upstream.
  Timer? _webViewLoadTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startFirestoreListener();
    _startWebViewLoadTimer();
  }

  @override
  void dispose() {
    _firestoreListener?.cancel();
    _webViewLoadTimer?.cancel();
    super.dispose();
  }

  // =============================================================================
  // WEBVIEW LOAD TIMEOUT (60s — bank page never rendered)
  // =============================================================================

  void _startWebViewLoadTimer() {
    _webViewLoadTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted || _resultHandled || _initialLoadDone) return;
      // Page never loaded — genuine network/gateway error
      if (mounted) {
        setState(() {
          _paymentStatus = _PaymentStatus.failed;
          _error = AppLocalizations.of(context).paymentPageLoadFailed;
        });
      }
    });
  }

  // =============================================================================
  // FIRESTORE FAST-PATH LISTENER
  // =============================================================================
  // Only active while the WebView is open. The moment any terminal status
  // arrives we cancel this and navigate. For the common case this fires
  // after the bank has already redirected (deep link wins the race), so
  // the double-handling guard makes both paths safe.

  void _startFirestoreListener() {
    _firestoreListener = FirebaseFirestore.instance
        .collection('pendingPayments')
        .doc(widget.orderNumber)
        .snapshots()
        .listen(
      (snap) {
        if (!snap.exists || _resultHandled || !mounted) return;
        final data = snap.data()!;
        final status = data['status'] as String?;

        switch (status) {
          case 'completed':
            _handlePaymentSuccess((data['orderId'] as String?) ?? '');
            break;
          case 'payment_failed':
          case 'hash_verification_failed':
            _handlePaymentFailed((data['errorMessage'] as String?) ?? '');
            break;
          case 'payment_succeeded_order_failed':
            // Payment was charged and our ops team has been alerted.
            // Navigate to orders — user should NOT be offered a retry.
            _handlePaymentProcessing();
            break;
        }
      },
      onError: (Object e) {
        debugPrint('[ProductPayment] Firestore listener error: $e');
      },
    );
  }

  // =============================================================================
  // DEEP LINK INTERCEPTION
  // =============================================================================

  Future<NavigationActionPolicy> _onShouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';

    if (url.startsWith('payment-success://')) {
      final orderId = Uri.decodeComponent(
        url.replaceFirst('payment-success://', ''),
      );
      _handlePaymentSuccess(orderId);
      return NavigationActionPolicy.CANCEL;
    }

    if (url.startsWith('payment-failed://')) {
      final message = Uri.decodeComponent(
        url.replaceFirst('payment-failed://', ''),
      );
      _handlePaymentFailed(message);
      return NavigationActionPolicy.CANCEL;
    }

    if (url.startsWith('payment-status://')) {
      // Any processing status → hand off to orders screen immediately.
      // The user should not wait here — orders screen owns the pending state.
      _handlePaymentProcessing();
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  // =============================================================================
  // RESULT HANDLERS
  // =============================================================================

  /// Called when the bank confirms payment AND the order was created.
  /// Fast path: navigate directly to orders, which will show a success banner.
  Future<void> _handlePaymentSuccess(String orderId) async {
    if (_resultHandled) return;
    _resultHandled = true;

    _firestoreListener?.cancel();
    _webViewLoadTimer?.cancel();
    _clearCart();

    if (!mounted) return;

    // Show a brief success overlay before navigating — gives visual feedback
    // and separates WebView disposal from the new route build.
    setState(() => _isNavigatingAway = true);

    final destination = orderId.isNotEmpty
        ? '/my_orders?pendingOrderId=${Uri.encodeComponent(orderId)}'
        : '/my_orders';

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) context.go(destination);
  }

  /// Called when the bank confirms payment but order creation is still
  /// in progress (or succeeded_order_failed — ops is notified either way).
  /// Navigate to orders screen which will watch Firestore and resolve itself.
  Future<void> _handlePaymentProcessing() async {
    if (_resultHandled) return;
    _resultHandled = true;

    _firestoreListener?.cancel();
    _webViewLoadTimer?.cancel();
    _clearCart();

    if (!mounted) return;

    // Show a brief processing overlay before navigating.
    setState(() => _isNavigatingAway = true);

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      context.go(
        '/my_orders?pendingOrderNumber=${Uri.encodeComponent(widget.orderNumber)}',
      );
    }
  }

  /// Called on a genuine payment failure (bank declined, hash mismatch).
  /// Stay on this screen so the user can try again.
  void _handlePaymentFailed(String message) {
    if (_resultHandled) return;
    _resultHandled = true;

    _firestoreListener?.cancel();
    _webViewLoadTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _paymentStatus = _PaymentStatus.failed;
      _error = message.trim().isEmpty
          ? AppLocalizations.of(context).paymentFailedDefault
          : message;
    });
  }

  // =============================================================================
  // HELPERS
  // =============================================================================

  void _clearCart() {
    try {
      if (mounted) {
        final cartProvider = context.read<CartProvider>();
        cartProvider.clearLocalCache();
        cartProvider.refresh();
      }
    } catch (e) {
      debugPrint('[ProductPayment] Cart clear failed (non-critical): $e');
    }
  }

  // =============================================================================
  // CANCEL HANDLER
  // =============================================================================

  Future<void> _handleCancel() async {
    // Already navigating away — nothing to do
    if (_resultHandled) return;

    // Genuine failure already shown — just pop
    if (_paymentStatus == _PaymentStatus.failed) {
      if (mounted) context.pop();
      return;
    }

    // Payment in progress — confirm before leaving
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _CancelDialog(isDark: _isDark),
    );

    if (!mounted) return;
    if (confirmed == true) context.pop();
    // If user wants to continue, payment keeps running — no restart needed
    // since we have no polling to resume.
  }

  // =============================================================================
  // POST FORM SUBMISSION
  // =============================================================================

  void _submitPostForm(InAppWebViewController controller) {
    final encoded = widget.paymentParams.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    controller.postUrl(
      url: WebUri(widget.gatewayUrl),
      postData: Uint8List.fromList(utf8.encode(encoded)),
    );
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;
    final l10n = AppLocalizations.of(context);

    // ── Navigating away: brief success / processing overlay ─────────────────
    if (_isNavigatingAway) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF00A86B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: Color(0xFF00A86B),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.paymentSuccessful,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Guard: missing params ────────────────────────────────────────────────
    if (widget.gatewayUrl.isEmpty || widget.orderNumber.isEmpty) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: l10n.paymentError,
        subtitle: _error ?? l10n.missingPaymentInfo,
        actions: [
          _PrimaryButton(label: l10n.goBack, onTap: () => context.pop()),
        ],
      );
    }

    // ── Failed screen (genuine bank decline / gateway error) ─────────────────
    if (_paymentStatus == _PaymentStatus.failed) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: l10n.paymentFailedTitle,
        subtitle: _error ?? l10n.paymentProcessingError,
        actions: [
          _PrimaryButton(label: l10n.tryAgain, onTap: () => context.pop()),
          TextButton(
            onPressed: () => context.go('/market'),
            child: Text(
              l10n.backToMarket,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
          ),
        ],
      );
    }

    // ── Active payment WebView ───────────────────────────────────────────────
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            _PaymentHeader(isDark: isDark, onCancel: _handleCancel),
            Expanded(
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
                            // Page loaded — WebView timeout no longer needed
                            _webViewLoadTimer?.cancel();
                          }
                        },
                        onReceivedError: (controller, request, error) {
                          debugPrint(
                            '[ProductPayment] WebView error: ${error.description}',
                          );
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
                                    color: const Color(0xFF00A86B)
                                        .withOpacity(0.5),
                                    strokeWidth: 4,
                                  ),
                                ),
                                const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00A86B),
                                    strokeWidth: 3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              l10n.loadingPaymentPage,
                              style: const TextStyle(
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
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded,
                          size: 13, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        l10n.secureSSLConnection,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.paymentProcessedByIsbank,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PAYMENT HEADER
// =============================================================================

class _PaymentHeader extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCancel;

  const _PaymentHeader({required this.isDark, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[900]!.withOpacity(0.8)
            : Colors.white.withOpacity(0.8),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.grey[700]!.withOpacity(0.5)
                : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.lock_rounded, size: 17, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            l10n.securePayment,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF00A86B).withOpacity(0.15)
                  : const Color(0xFFE8F8F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_bag_rounded,
                  size: 13,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF00A86B),
                ),
                const SizedBox(width: 5),
                Text(
                  l10n.marketOrder,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF00A86B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FULL SCREEN MESSAGE
// =============================================================================

class _FullScreenMessage extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final Color? iconBgColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final List<Widget> actions;

  const _FullScreenMessage({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.iconBgColor,
    this.trailing,
    this.footer,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB),
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
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(height: 8),
                trailing!,
              ],
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
          backgroundColor: const Color(0xFF00A86B),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
          color: isDark ? Colors.white : Colors.grey[900],
        ),
      ),
      content: Text(
        l10n.cancelPaymentMessage,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.continuePayment,
            style: TextStyle(
              color: isDark ? Colors.grey[300] : Colors.grey[700],
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
            l10n.cancelPaymentButton,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}