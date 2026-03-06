import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../../generated/l10n/app_localizations.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class IsbankAdsImagesPaymentScreen extends StatefulWidget {
  final String submissionId;
  final String paymentLink;
  final double price;

  const IsbankAdsImagesPaymentScreen({
    Key? key,
    required this.submissionId,
    required this.paymentLink,
    required this.price,
  }) : super(key: key);

  @override
  State<IsbankAdsImagesPaymentScreen> createState() =>
      _IsbankAdsImagesPaymentScreenState();
}

class _IsbankAdsImagesPaymentScreenState
    extends State<IsbankAdsImagesPaymentScreen> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _isInitializing = true;

  // Only set for genuine fatal errors — NOT for cross-origin redirect errors
  // which are non-fatal during 3D Secure flow
  String? _fatalError;

  bool _isNavigating = false;

  String? _gatewayUrl;
  Map<String, dynamic>? _paymentParams;
  String? _orderNumber;

  Timer? _pollTimer;
  int _pollCount = 0;

  // ── Init ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializePayment();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Payment initialization ────────────────────────────────────────────────────

  Future<void> _initializePayment() async {
    setState(() {
      _isInitializing = true;
      _fatalError = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('initializeIsbankAdPayment');

      final result = await callable.call({
        'submissionId': widget.submissionId,
        'paymentLink': widget.paymentLink,
      });

      final responseData = Map<String, dynamic>.from(result.data as Map);

      if (responseData['success'] == true) {
        setState(() {
          _gatewayUrl = responseData['gatewayUrl'] as String?;
          _paymentParams =
              Map<String, dynamic>.from(responseData['paymentParams'] as Map);
          _orderNumber = responseData['orderNumber'] as String?;
          _isInitializing = false;
        });

        _initializeWebView();
        _startPolling();
      } else {
        throw Exception('Payment initialization failed');
      }
    } catch (e) {
      debugPrint('[AdsPayment] Init error: $e');
      setState(() {
        _fatalError = e.toString();
        _isInitializing = false;
      });
    }
  }

  // ── Adaptive polling ──────────────────────────────────────────────────────────
  // First 15 polls: every 2s (30s) — bank callback fires here
  // Next 30 polls: every 5s (150s) — ~3 min total, ~45 calls max

  void _startPolling() {
    _pollTimer?.cancel();
    _pollCount = 0;
    _scheduleNextPoll();
  }

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
    if (!mounted || _isNavigating) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).paymentTimeout),
        content: Text(AppLocalizations.of(context).paymentTimeoutMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) context.pop();
            },
            child: Text(AppLocalizations.of(context).ok),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPaymentStatus() async {
    if (_isNavigating || _orderNumber == null) return;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('checkIsbankAdPaymentStatus');

      final result = await callable.call({'orderNumber': _orderNumber});
      final responseData = Map<String, dynamic>.from(result.data as Map);
      final status = responseData['status'] as String?;

      debugPrint('[AdsPayment] Status: $status');

      switch (status) {
        case 'completed':
          _handlePaymentSuccess();
          break;

        case 'payment_failed':
        case 'hash_verification_failed':
          _handlePaymentFailure(
              responseData['errorMessage'] as String? ?? AppLocalizations.of(context).paymentFailedDefault);
          break;

        case 'payment_succeeded_activation_failed':
        case 'refunded':
          // Auto-refund has been issued by the backend
          _handlePaymentFailure(AppLocalizations.of(context).paymentReceivedAdFailed);
          break;

        // 'processing', 'awaiting_3d' — keep waiting
      }
    } catch (e) {
      // Transient error — keep polling
      debugPrint('[AdsPayment] Status check error: $e');
    }
  }

  // ── Success ───────────────────────────────────────────────────────────────────

  void _handlePaymentSuccess() {
    if (_isNavigating || !mounted) return;
    setState(() => _isNavigating = true);
    _pollTimer?.cancel();

    debugPrint('[AdsPayment] Success. Submission: ${widget.submissionId}');

    // Navigate to success screen directly — do NOT pop then show dialog
    // (popping first leaves context in invalid state for the dialog)
    if (mounted) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF38A169), Color(0xFF2F855A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 48, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.paymentSuccessful,
              style: GoogleFonts.figtree(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A202C)),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.adPaymentSuccessMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.figtree(
                  fontSize: 14, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // Single authoritative navigation — no prior pop needed
                context.go('/seller-panel');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38A169),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(l10n.gotIt,
                  style: GoogleFonts.figtree(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Failure ───────────────────────────────────────────────────────────────────

  void _handlePaymentFailure(String message) {
    if (_isNavigating || !mounted) return;
    setState(() => _isNavigating = true);
    _pollTimer?.cancel();

    debugPrint('[AdsPayment] Failure: $message');
    _showErrorDialog(message);
  }

  // ── WebView ───────────────────────────────────────────────────────────────────

  void _initializeWebView() {
    if (_gatewayUrl == null || _paymentParams == null) return;

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
            debugPrint('[AdsPayment] Page finished: $url');
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

            if (request.url.startsWith('ad-payment-success://')) {
              _handlePaymentSuccess();
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith('ad-payment-failed://')) {
              final error = Uri.decodeComponent(
                  request.url.replaceFirst('ad-payment-failed://', ''));
              _handlePaymentFailure(error);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.dataFromString(
          _generatePaymentForm(
            loadingText: l10n.loadingSecurePaymentPage,
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
    required String secureBadgeText,
  }) {
    final formFields = _paymentParams!.entries
        .map((e) =>
            '<input type="hidden" name="${_escapeHtml(e.key)}" value="${_escapeHtml(e.value.toString())}">')
        .join('\n');

    final safeGatewayUrl = _escapeHtml(_gatewayUrl!);

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
          .loading-container { text-align: center; color: white; padding: 40px; }
          .spinner {
            width: 50px; height: 50px; margin: 0 auto 20px;
            border: 4px solid rgba(255,255,255,0.3);
            border-top-color: white; border-radius: 50%;
            animation: spin 1s linear infinite;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
          .loading-text { font-size: 18px; font-weight: 500; margin: 0; }
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
                style: GoogleFonts.figtree(
                    fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(message,
            style: GoogleFonts.figtree(
                fontSize: 16, color: const Color(0xFF64748B))),
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
            child: Text(l10n.ok,
                style: GoogleFonts.figtree(
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
            style: GoogleFonts.figtree(
                fontSize: 20, fontWeight: FontWeight.w600)),
        content: Text(l10n.cancelPaymentMessage,
            style: GoogleFonts.figtree(
                fontSize: 16, color: const Color(0xFF64748B))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.no,
                style: GoogleFonts.figtree(
                    fontSize: 16, color: const Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.yes,
                style: GoogleFonts.figtree(
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
      backgroundColor:
          isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor:
            isDark ? const Color(0xFF1A1B23) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          // Disable X while payment is initialising
          onPressed: _isInitializing ? null : _showCancelDialog,
        ),
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(
              l10n.securePayment,
              style: GoogleFonts.figtree(
                color: isDark ? Colors.white : const Color(0xFF1A202C),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(isDark, l10n),
    );
  }

  Widget _buildBody(bool isDark, AppLocalizations l10n) {
    if (_isInitializing) return _buildInitializingView(isDark, l10n);

    // Fatal error during init or WebView load
    if (_fatalError != null) return _buildErrorView(isDark, l10n);

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) _buildLoadingOverlay(isDark, l10n),
      ],
    );
  }

  Widget _buildInitializingView(bool isDark, AppLocalizations l10n) {
    return Container(
      color: isDark ? const Color(0xFF0F0F23) : const Color(0xFFF8FAFC),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.initializingPayment,
              style: GoogleFonts.figtree(
                fontSize: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(bool isDark, AppLocalizations l10n) {
    return Container(
      color: isDark ? const Color(0xFF0F0F23) : Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.loadingPaymentPage,
              style: GoogleFonts.figtree(
                fontSize: 16,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(bool isDark, AppLocalizations l10n) {
    return Container(
      color: isDark ? const Color(0xFF0F0F23) : Colors.white,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 24),
            Text(
              l10n.connectionError,
              style: GoogleFonts.figtree(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A202C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _fatalError!,
              style: GoogleFonts.figtree(
                fontSize: 14,
                color: isDark ? Colors.white70 : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _initializePayment,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
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
    );
  }
}