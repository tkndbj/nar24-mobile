import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import 'dart:convert';
import '../../generated/l10n/app_localizations.dart';

class BoostPaymentWebView extends StatefulWidget {
  final String gatewayUrl;
  final Map<String, dynamic> paymentParams;
  final String orderNumber;

  const BoostPaymentWebView({
    Key? key,
    required this.gatewayUrl,
    required this.paymentParams,
    required this.orderNumber,
  }) : super(key: key);

  @override
  State<BoostPaymentWebView> createState() => _BoostPaymentWebViewState();
}

class _BoostPaymentWebViewState extends State<BoostPaymentWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  // Only set for genuine fatal errors — NOT cross-origin redirect errors
  // which are non-fatal during 3D Secure flow
  String? _fatalError;

  bool _isNavigating = false;

  Timer? _pollTimer;
  int _pollCount = 0;

  // ── Init ──────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _scheduleNextPoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Adaptive polling ──────────────────────────────────────────────────────────
  // First 15 polls: every 2s (30s) — bank callback fires here
  // Next 30 polls: every 5s (150s) — ~3 min total, ~45 calls max

  void _scheduleNextPoll() {
    if (!mounted) return;
    final delay = _pollCount < 15
        ? const Duration(seconds: 2)
        : const Duration(seconds: 5);

    _pollTimer = Timer(delay, () async {
      if (!mounted) return;
      _pollCount++;

      if (_pollCount > 45) {
        if (mounted && !_isNavigating) _handleTimeout();
        return;
      }

      await _checkPaymentStatus();

      if (mounted && !_isNavigating) _scheduleNextPoll();
    });
  }

  void _handleTimeout() {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    _pollTimer?.cancel();

    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.paymentTimeout,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        content: Text(l10n.paymentTimeoutMessage,
            style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) Navigator.of(context).pop('failed');
            },
            child: Text(l10n.ok,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPaymentStatus() async {
    if (_isNavigating) return;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('checkBoostPaymentStatus');

      final result =
          await callable.call({'orderNumber': widget.orderNumber});
      final responseData = Map<String, dynamic>.from(result.data as Map);
      final status = responseData['status'] as String?;

      debugPrint('[BoostPayment] Status: $status');

      switch (status) {
        case 'completed':
          _handleSuccess();
          break;

        case 'payment_failed':
        case 'hash_verification_failed':
          _handleFailure(
              responseData['errorMessage'] as String? ?? AppLocalizations.of(context).paymentFailedDefault);
          break;

        case 'payment_succeeded_boost_failed':
        case 'refunded':
          // Auto-refund has been issued by the backend
          _handleFailure(AppLocalizations.of(context).paymentReceivedBoostFailed);
          break;

        // 'processing', 'awaiting_3d' — keep waiting
      }
    } catch (e) {
      // Transient error — keep polling
      debugPrint('[BoostPayment] Status check error: $e');
    }
  }

  // ── Success ───────────────────────────────────────────────────────────────────
  // Returns 'success' to the caller — the CALLER is responsible for showing
  // the SnackBar on its own context. Showing it here after pop is unreliable.

  void _handleSuccess() {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    _pollTimer?.cancel();

    debugPrint('[BoostPayment] Success');
    Navigator.of(context).pop('success');
  }

  // ── Failure ───────────────────────────────────────────────────────────────────

  void _handleFailure(String message) {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    _pollTimer?.cancel();

    debugPrint('[BoostPayment] Failure: $message');
    _showErrorDialog(message);
  }

  // ── WebView ───────────────────────────────────────────────────────────────────

  void _initializeWebView() {
    final l10n = AppLocalizations.of(context);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            debugPrint('[BoostPayment] Page finished: $url');
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // Cross-origin redirects during 3D Secure produce resource errors
            // that are completely non-fatal. Only surface genuine load failures
            // on the initial page (errorCode -1 and 102 are redirect-related).
            if (mounted && _isLoading) {
              setState(() => _isLoading = false);
              if (error.errorCode != -1 && error.errorCode != 102) {
                setState(() => _fatalError = error.description);
              }
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_isNavigating) return NavigationDecision.prevent;

            // Backup: custom URL scheme in case polling is slow
            if (request.url.startsWith('boost-payment-success://')) {
              _handleSuccess();
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith('boost-payment-failed://')) {
              final error = Uri.decodeComponent(
                  request.url.replaceFirst('boost-payment-failed://', ''));
              _handleFailure(error);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.dataFromString(
          _generatePaymentForm(
            loadingText: l10n.boostPaymentLoading,
            boostBadgeText: l10n.boostPackage,
            secureBadgeText: l10n.secureConnectionBadge,
          ),
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
    required String boostBadgeText,
    required String secureBadgeText,
  }) {
    final formFields = widget.paymentParams.entries
        .map((e) =>
            '<input type="hidden" name="${_escapeHtml(e.key)}" value="${_escapeHtml(e.value.toString())}">')
        .join('\n');

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
            margin: 0; padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #00A86B 0%, #008F5A 100%);
            min-height: 100vh; display: flex;
            align-items: center; justify-content: center;
          }
          .loading-container { text-align: center; color: white; padding: 40px; }
          .spinner {
            width: 50px; height: 50px; margin: 0 auto 20px;
            border: 4px solid rgba(255,255,255,0.3);
            border-top-color: white; border-radius: 50%;
            animation: spin 1s linear infinite;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
          .loading-text { font-size: 18px; font-weight: 500; margin: 0; }
          .boost-badge {
            display: inline-block; background: rgba(255,255,255,0.15);
            padding: 6px 14px; border-radius: 16px;
            margin-top: 12px; font-size: 13px; font-weight: 600;
          }
          .secure-badge {
            display: inline-flex; align-items: center; gap: 8px;
            background: rgba(255,255,255,0.2); padding: 8px 16px;
            border-radius: 20px; margin-top: 20px; font-size: 14px;
          }
        </style>
      </head>
      <body>
        <div class="loading-container">
          <div class="spinner"></div>
          <p class="loading-text">${_escapeHtml(loadingText)}</p>
          <div class="boost-badge">🚀 ${_escapeHtml(boostBadgeText)}</div>
          <div class="secure-badge">🔒 ${_escapeHtml(secureBadgeText)}</div>
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

  // ── Dialogs ───────────────────────────────────────────────────────────────────

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
            Text(l10n.paymentError,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(message,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) Navigator.of(context).pop('failed');
            },
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(l10n.ok,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
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
        title: Text(l10n.cancelPaymentTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        content: Text(l10n.boostPaymentCancelMessage,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.no,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) Navigator.of(context).pop('cancelled');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.yes,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              l10n.secureBoostPayment,
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
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
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
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
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