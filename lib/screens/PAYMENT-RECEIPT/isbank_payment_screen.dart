import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../../generated/l10n/app_localizations.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class IsbankPaymentScreen extends StatefulWidget {
  final String gatewayUrl;
  final Map<String, dynamic> paymentParams;
  final String orderNumber;

  const IsbankPaymentScreen({
    Key? key,
    required this.gatewayUrl,
    required this.paymentParams,
    required this.orderNumber,
  }) : super(key: key);

  @override
  State<IsbankPaymentScreen> createState() => _IsbankPaymentScreenState();
}

class _IsbankPaymentScreenState extends State<IsbankPaymentScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  // Only set for genuine fatal errors (connection lost, etc.)
  // NOT set for cross-origin redirect errors which are non-fatal mid-payment
  String? _fatalError;

  bool _isNavigating = false;
  String? _completedOrderId;

  StreamSubscription<DocumentSnapshot>? _paymentListener;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startPaymentListener();
    _startTimeoutTimer();
  }

  // ── Firestore real-time listener ─────────────────────────────────────────────
  void _startPaymentListener() {
    debugPrint('[IsbankPayment] Starting listener for ${widget.orderNumber}');

    _paymentListener = FirebaseFirestore.instance
        .collection('pendingPayments')
        .doc(widget.orderNumber)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted || _isNavigating) return;
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final status = data['status'] as String?;
        final orderId = data['orderId'] as String?;
        final errorMessage = data['errorMessage'] as String?;

        debugPrint('[IsbankPayment] Status changed: $status');

        switch (status) {
          case 'completed':
            if (orderId != null) {
              _completedOrderId = orderId;
              _handlePaymentSuccess();
            }
            break;

          case 'payment_failed':
          case 'hash_verification_failed':
            _handlePaymentFailure(errorMessage ?? AppLocalizations.of(context).paymentFailedDefault);
            break;

          case 'payment_succeeded_order_failed':
          case 'refunded':
            // Auto-refund has been (or is being) issued by the backend
            _handlePaymentFailure(AppLocalizations.of(context).paymentReceivedOrderFailed);
            break;

          case 'processing':
          case 'payment_verified_processing_order':
            // Actively being processed — just wait
            debugPrint('[IsbankPayment] Processing...');
            break;

          // 'awaiting_3d' is the initial state — do nothing
        }
      },
      onError: (error) {
        _logError('Listener error: $error');
      },
    );
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(const Duration(minutes: 10), () {
      if (mounted && !_isNavigating) _handleTimeout();
    });
  }

  void _handleTimeout() {
    if (!mounted || _isNavigating) return;
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.paymentTimeout),
        content: Text(l10n.paymentTimeoutMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.pop();
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  // ── Success ──────────────────────────────────────────────────────────────────
  void _handlePaymentSuccess() {
    if (_isNavigating || !mounted) return;
    setState(() => _isNavigating = true);
    _cleanup();

    debugPrint('[IsbankPayment] Success. Order: $_completedOrderId');

    // Clear cart (non-critical)
    try {
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      cartProvider.clearLocalCache();
      cartProvider.refresh();
    } catch (e) {
      debugPrint('[IsbankPayment] Cart clear failed (non-critical): $e');
    }

    if (!mounted) return;

    // Single navigation call — no pop+push which can land on wrong stack
    context.pushReplacement(
      '/product-payment-success',
      extra: {'orderId': _completedOrderId},
    );
  }

  // ── Failure ──────────────────────────────────────────────────────────────────
  void _handlePaymentFailure(String message) {
    if (_isNavigating || !mounted) return;
    setState(() => _isNavigating = true);
    _cleanup();

    _logError(message);
    _showErrorDialog(message);
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────────
  void _cleanup() {
    _paymentListener?.cancel();
    _paymentListener = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  // ── Logging ──────────────────────────────────────────────────────────────────
  void _logError(String error) {
    try {
      FirebaseFirestore.instance.collection('_client_errors').add({
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'context': 'isbank_payment_screen',
        'error': error,
        'orderNumber': widget.orderNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silent
    }
  }

  // ── WebView ──────────────────────────────────────────────────────────────────
  void _initializeWebView() {
    final l10n = AppLocalizations.of(context);
    final html = _generatePaymentForm(
      loadingText: l10n.loadingSecurePaymentPage,
      secureBadgeText: l10n.secureConnectionBadge,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            debugPrint('[IsbankPayment] Page finished: $url');
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // Cross-origin redirects during 3D Secure flow produce resource
            // errors that are completely non-fatal. Only surface errors that
            // occur on the initial page load (before the user has interacted).
            if (mounted && _isLoading) {
              setState(() => _isLoading = false);
              // Only show fatal error if not a redirect-related error
              if (error.errorCode != -1 && error.errorCode != 102) {
                setState(() => _fatalError = error.description);
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_isNavigating) return NavigationDecision.prevent;

            // Backup: custom URL scheme in case Firestore listener is slow
            if (request.url.startsWith('payment-success://')) {
              final orderId =
                  request.url.replaceFirst('payment-success://', '');
              if (orderId.isNotEmpty) _completedOrderId = orderId;
              _handlePaymentSuccess();
              return NavigationDecision.prevent;
            }

            if (request.url.startsWith('payment-failed://')) {
              final error = Uri.decodeComponent(
                  request.url.replaceFirst('payment-failed://', ''));
              _handlePaymentFailure(error);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.dataFromString(
          html,
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8'),
        ),
      );
  }

  // HTML-escape helper — prevents XSS from param values containing " or <
  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  String _generatePaymentForm({
    required String loadingText,
    required String secureBadgeText,
  }) {
    final formFields = widget.paymentParams.entries
        .map((e) =>
            '<input type="hidden" name="${_escapeHtml(e.key)}" value="${_escapeHtml(e.value.toString())}">')
        .join('\n');

    // gatewayUrl is also escaped in the action attribute
    final safeGatewayUrl = _escapeHtml(widget.gatewayUrl);

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Güvenli Ödeme</title>
        <style>
          body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .loading-container {
            text-align: center;
            color: white;
            padding: 40px;
          }
          .spinner {
            width: 50px;
            height: 50px;
            margin: 0 auto 20px;
            border: 4px solid rgba(255, 255, 255, 0.3);
            border-top-color: white;
            border-radius: 50%;
            animation: spin 1s linear infinite;
          }
          @keyframes spin {
            to { transform: rotate(360deg); }
          }
          .loading-text {
            font-size: 18px;
            font-weight: 500;
            margin: 0;
          }
          .secure-badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(255, 255, 255, 0.2);
            padding: 8px 16px;
            border-radius: 20px;
            margin-top: 20px;
            font-size: 14px;
          }
        </style>
      </head>
      <body>
        <div class="loading-container">
          <div class="spinner"></div>
          <p class="loading-text">${_escapeHtml(loadingText)}</p>
          <div class="secure-badge">
            🔒 ${_escapeHtml(secureBadgeText)}
          </div>
        </div>
        <form id="paymentForm" method="post" action="$safeGatewayUrl">
          $formFields
        </form>
        <script>
          setTimeout(() => document.getElementById('paymentForm').submit(), 1500);
        </script>
      </body>
      </html>
    ''';
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────────
  void _showErrorDialog(String message) {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 28),
            const SizedBox(width: 12),
            Text(
              l10n.paymentError,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              l10n.ok,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    // Payment already resolved — X button should do nothing
    if (_isNavigating) return;

    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.cancelPaymentTitle,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        content: Text(
          l10n.cancelPaymentMessage,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.no,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              l10n.yes,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          onPressed: _showCancelDialog,
        ),
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(
              l10n.securePayment,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

          // Loading overlay
          if (_isLoading)
            Container(
              color: isDark ? const Color(0xFF1C1A29) : Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF00A86B)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.loadingPaymentPage,
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            isDark ? Colors.white70 : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Fatal error overlay (genuine connection failures only)
          if (_fatalError != null && !_isLoading)
            Container(
              color: isDark ? const Color(0xFF1C1A29) : Colors.white,
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 64, color: Colors.red.shade400),
                    const SizedBox(height: 24),
                    Text(
                      l10n.connectionError,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fatalError!,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _fatalError = null;
                          _initializeWebView();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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