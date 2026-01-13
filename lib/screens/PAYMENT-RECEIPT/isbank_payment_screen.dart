import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../../generated/l10n/app_localizations.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';

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
  String? _errorMessage;
  bool _isNavigating = false;
  String? _completedOrderId;
  
  // ✅ Real-time listener instead of polling
  StreamSubscription<DocumentSnapshot>? _paymentListener;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startPaymentListener();
    _startTimeoutTimer();
  }

  /// ✅ Real-time Firestore listener - instant response
  void _startPaymentListener() {
    print('🔴 Starting payment status listener for ${widget.orderNumber}');
    
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
            
            print('🔔 Payment status changed: $status');
            
            switch (status) {
              case 'completed':
                if (orderId != null) {
                  _completedOrderId = orderId;
                  _handlePaymentSuccess();
                }
                break;
                
              case 'payment_failed':
              case 'hash_verification_failed':
                _handlePaymentFailure(errorMessage ?? 'Payment failed');
                break;
                
              case 'payment_succeeded_order_failed':
                _handlePaymentFailure(
                  'Payment was successful but order creation failed. '
                  'Please contact support with reference: ${widget.orderNumber}'
                );
                break;
                
              case 'processing':
              case 'payment_verified_processing_order':
                // Payment is being processed - just wait
                print('⏳ Payment processing...');
                break;
                
              // 'awaiting_3d' is the initial state - do nothing
            }
          },
          onError: (error) {
            print('❌ Payment listener error: $error');
            // Don't fail - WebView URL scheme is backup
          },
        );
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(const Duration(minutes: 10), () {
      if (mounted && !_isNavigating) {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (mounted && !_isNavigating) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Payment Timeout'),
          content: const Text('The payment session has expired. Please try again.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(false);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _handlePaymentSuccess() {
    if (_isNavigating || !mounted) return;

    setState(() => _isNavigating = true);
    _cleanup();

    print('✅ Payment completed! Order ID: $_completedOrderId');

    // Clear cart cache
    try {
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      cartProvider.clearLocalCache();
    } catch (e) {
      debugPrint('Could not clear cart cache: $e');
    }

    Navigator.of(context).pop(true);

    if (_completedOrderId != null && mounted) {
      context.pushReplacement('/product-payment-success',
          extra: {'orderId': _completedOrderId});
    }
  }

  void _handlePaymentFailure(String errorMessage) {
    if (_isNavigating || !mounted) return;

    setState(() => _isNavigating = true);
    _cleanup();

    print('❌ Payment failed: $errorMessage');

    _showErrorDialog(errorMessage);
  }

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
          },
          onPageFinished: (url) {
            print('📄 Page finished loading: $url');
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
            if (_isNavigating) return NavigationDecision.prevent;

            // ✅ Backup: Custom URL scheme (in case Firestore listener misses)
            if (request.url.startsWith('payment-success://')) {
              final orderId = request.url.replaceFirst('payment-success://', '');
              if (orderId.isNotEmpty) {
                _completedOrderId = orderId;
              }
              _handlePaymentSuccess();
              return NavigationDecision.prevent;
            } else if (request.url.startsWith('payment-failed://')) {
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
          <p class="loading-text">Güvenli Ödeme sayfası yükleniyor...</p>
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
            Text(
              l10n.paymentError,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
              Navigator.pop(context, false);
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
              Navigator.pop(context, false);
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
                      label: Text(l10n.retry),
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