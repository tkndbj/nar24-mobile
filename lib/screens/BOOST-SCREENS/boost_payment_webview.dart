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
  String? _errorMessage;
  Timer? _statusCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startStatusPolling();
  }

  void _initializeWebView() {
    final html = _generatePaymentForm();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
            _handleNavigation(url);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = error.description;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
  if (request.url.startsWith('boost-payment-success://')) {
    _statusCheckTimer?.cancel();
    _showSuccessAndReturn();
    return NavigationDecision.prevent;
  } else if (request.url.startsWith('boost-payment-failed://')) {
    _statusCheckTimer?.cancel();
    final error = request.url.replaceFirst('boost-payment-failed://', '');
    _showErrorDialog(Uri.decodeComponent(error));
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

  String _generatePaymentForm() {
    final formFields = widget.paymentParams.entries
        .map((e) => '<input type="hidden" name="${e.key}" value="${e.value}">')
        .join('\n');

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
            background: linear-gradient(135deg, #00A86B 0%, #008F5A 100%);
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
          .boost-badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.15);
            padding: 6px 14px;
            border-radius: 16px;
            margin-top: 12px;
            font-size: 13px;
            font-weight: 600;
          }
        </style>
      </head>
      <body>
        <div class="loading-container">
          <div class="spinner"></div>
          <p class="loading-text">Boost Ödeme sayfası yükleniyor...</p>
          <div class="boost-badge">🚀 Boost Paketi</div>
          <div class="secure-badge">
            🔒 Güvenli Bağlantı
          </div>
        </div>
        <form id="paymentForm" method="post" action="${widget.gatewayUrl}">
          $formFields
        </form>
        <script>
          setTimeout(() => document.getElementById('paymentForm').submit(), 1500);
        </script>
      </body>
      </html>
    ''';
  }

  void _startStatusPolling() {
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkPaymentStatus();
    });
  }

 Future<void> _checkPaymentStatus() async {
  try {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
        .httpsCallable('checkBoostPaymentStatus');

    final result = await callable.call({
      'orderNumber': widget.orderNumber,
    });

    final responseData = Map<String, dynamic>.from(result.data as Map);
    final status = responseData['status'];

    if (status == 'completed') {
      _statusCheckTimer?.cancel();
      if (mounted) {
        _showSuccessAndReturn();
      }
    } else if (status == 'payment_failed' || 
               status == 'hash_verification_failed' ||
               status == 'payment_succeeded_boost_failed') {
      _statusCheckTimer?.cancel();
      if (mounted) {
        Navigator.of(context).pop('failed');
      }
    }
  } catch (e) {
    print('Error checking payment status: $e');
  }
}

 void _handleNavigation(String url) {
  if (url.contains('boost-payment-success://')) {
    _statusCheckTimer?.cancel();
    _showSuccessAndReturn();
  } else if (url.contains('boost-payment-failed://')) {
    _statusCheckTimer?.cancel();
    Navigator.of(context).pop('failed');
  }
}

void _showSuccessAndReturn() {
  if (!mounted) return;
  final l10n = AppLocalizations.of(context);
  // Pop the payment screen
  Navigator.of(context).pop('success');
  
  // Show success message after a short delay to ensure we're back on the boost screen
  Future.delayed(const Duration(milliseconds: 300), () {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.paymentSuccessful,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'Figtree',
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    l10n.yourProductsAreNowBoosted,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontFamily: 'Figtree',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00A86B),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 4),
        elevation: 8,
      ),
    );
  });
}

  void _showErrorDialog(String message) {
    if (!mounted) return;
    
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Ödeme Hatası',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
              Navigator.pop(context);
              Navigator.pop(context, 'failed');
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              l10n.ok,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Ödemeyi İptal Et?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Boost ödemesi iptal edilecek. Emin misiniz?',
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
              Navigator.pop(context, 'cancelled');
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text(
              l10n.yes,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }

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
            Icon(
              Icons.lock_outline,
              size: 20,
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              'Güvenli Boost Ödemesi',
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
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A86B)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Ödeme sayfası yükleniyor...',
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
          
          // Error overlay
          if (_errorMessage != null && !_isLoading)
            Container(
              color: isDark ? const Color(0xFF1C1A29) : Colors.white,
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Bağlantı Hatası',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
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
                          _errorMessage = null;
                          _initializeWebView();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A86B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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