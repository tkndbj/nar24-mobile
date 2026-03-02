// lib/screens/food/food_payment_screen.dart
//
// Mirrors: app/isbankfoodpayment/page.tsx (FoodPaymentContent)
//
// Route — add to your GoRouter alongside food-checkout:
// GoRoute(
//   path: '/isbankfoodpayment',
//   name: 'isbankfoodpayment',
//   pageBuilder: (context, state) {
//     final extra = state.extra as Map<String, dynamic>;
//     return CustomTransitionPage(
//       key: state.pageKey,
//       child: FoodPaymentScreen(
//         gatewayUrl: extra['gatewayUrl'] as String,
//         orderNumber: extra['orderNumber'] as String,
//         paymentParams: Map<String, String>.from(extra['paymentParams'] as Map),
//       ),
//       transitionsBuilder: _slideTransition,
//       transitionDuration: const Duration(milliseconds: 200),
//     );
//   },
// ),

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../providers/food_cart_provider.dart';

// =============================================================================
// ENTRY POINT
// =============================================================================

class FoodPaymentScreen extends StatefulWidget {
  final String gatewayUrl;
  final String orderNumber;
  final Map<String, String> paymentParams;

  const FoodPaymentScreen({
    super.key,
    required this.gatewayUrl,
    required this.orderNumber,
    required this.paymentParams,
  });

  @override
  State<FoodPaymentScreen> createState() => _FoodPaymentScreenState();
}

// =============================================================================
// STATE
// =============================================================================

enum _PaymentStatus { pending, completed, failed, timeout }

class _FoodPaymentScreenState extends State<FoodPaymentScreen> {
  late final WebViewController _webController;

  _PaymentStatus _paymentStatus = _PaymentStatus.pending;
  bool _isLoading = true;
  String? _error;
  String _successOrderId = '';

  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 300; // 5 minutes at 1s interval

  @override
  void initState() {
    super.initState();
    _initWebView();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── WebView init + POST form submit ─────────────────────────────────────────
  // Mirrors: submitPaymentForm() — builds a POST body and loads it into the WebView
  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (error) {
          // Non-fatal — the gateway may redirect to a different origin
          debugPrint(
              '[FoodPayment] WebView resource error: ${error.description}');
        },
      ));

    // Small delay mirrors the 1200ms timeout in the web version
    Future.delayed(const Duration(milliseconds: 1200), _submitPostForm);
  }

  void _submitPostForm() {
    if (!mounted) return;

    // Encode params as application/x-www-form-urlencoded
    final encoded = widget.paymentParams.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    _webController.loadRequest(
      Uri.parse(widget.gatewayUrl),
      method: LoadRequestMethod.post,
      body: Uint8List.fromList(utf8.encode(encoded)),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );
  }

  // ── Polling  —  mirrors startStatusPolling / checkPaymentStatus ─────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      _pollCount++;

      if (_pollCount > _maxPolls) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _paymentStatus = _PaymentStatus.timeout;
            _error = 'Payment timed out. Please try again.';
          });
        }
        return;
      }

      await _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('checkFoodPaymentStatus');
      final result = await fn.call({'orderNumber': widget.orderNumber});
      final data = result.data as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status == 'completed') {
        _pollTimer?.cancel();

        // Clear cart (non-critical)
        try {
          await context.read<FoodCartProvider>().clearCart();
        } catch (e) {
          debugPrint('[FoodPayment] Cart clear failed (non-critical): $e');
        }

        if (mounted) {
          setState(() {
            _paymentStatus = _PaymentStatus.completed;
            _successOrderId = (data['orderId'] as String?) ?? '';
          });
        }

        // Navigate after brief success display — mirrors setTimeout 2000ms
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          context.go('/food-orders?success=true&orderId=$_successOrderId');
        }
      } else if (status == 'payment_failed' ||
          status == 'hash_verification_failed' ||
          status == 'payment_succeeded_order_failed') {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _paymentStatus = _PaymentStatus.failed;
            _error = (data['errorMessage'] as String?) ?? 'Payment failed.';
          });
        }
      }
    } on FirebaseFunctionsException catch (e) {
      // Transient error — keep polling (mirrors web's "don't stop polling" comment)
      debugPrint('[FoodPayment] Status check error: ${e.message}');
    } catch (e) {
      debugPrint('[FoodPayment] Status check error: $e');
    }
  }

  // ── Cancel handler  —  mirrors handleCancel ─────────────────────────────────
  Future<void> _handleCancel() async {
    _pollTimer?.cancel();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _CancelDialog(isDark: _isDark),
    );

    if (confirmed == true) {
      if (mounted) context.pop();
    } else {
      // Resume polling
      _startPolling();
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark;

    // ── Missing params (shouldn't happen but guard anyway) ──────────────────
    if (widget.gatewayUrl.isEmpty || widget.orderNumber.isEmpty) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: 'Payment Error',
        subtitle: _error ?? 'Missing payment information.',
        actions: [
          _OrangeButton(label: 'Go Back', onTap: () => context.pop()),
        ],
      );
    }

    // ── Success ─────────────────────────────────────────────────────────────
    if (_paymentStatus == _PaymentStatus.completed) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.check_circle_rounded,
        iconColor: Colors.green,
        iconBgColor: Colors.green.withOpacity(0.15),
        title: 'Payment Successful',
        subtitle: 'Your order has been sent to the restaurant.',
        trailing: _successOrderId.isNotEmpty
            ? Text(
                'Order: ${_successOrderId.substring(0, _successOrderId.length.clamp(0, 8)).toUpperCase()}',
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[400]),
              )
            : null,
        footer: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.orange, strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Redirecting…',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange)),
        ]),
      );
    }

    // ── Failed / Timeout ─────────────────────────────────────────────────────
    if (_paymentStatus == _PaymentStatus.failed ||
        _paymentStatus == _PaymentStatus.timeout ||
        (_error != null && _paymentStatus != _PaymentStatus.pending)) {
      return _FullScreenMessage(
        isDark: isDark,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        title: _paymentStatus == _PaymentStatus.timeout
            ? 'Payment Timed Out'
            : 'Payment Failed',
        subtitle: _error ?? 'An error occurred while processing your payment.',
        actions: [
          _OrangeButton(label: 'Try Again', onTap: () => context.pop()),
          TextButton(
            onPressed: () => context.go('/restaurants'),
            child: Text('Back to Restaurants',
                style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[500])),
          ),
        ],
      );
    }

    // ── Active payment WebView ───────────────────────────────────────────────
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFFFFBF5),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _PaymentHeader(
              isDark: isDark,
              onCancel: _handleCancel,
            ),

            // ── WebView + loading overlay ────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // WebView
                  Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isDark
                              ? Colors.grey[700]!.withOpacity(0.5)
                              : Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: WebViewWidget(controller: _webController),
                    ),
                  ),

                  // Loading overlay — mirrors the isLoading overlay
                  if (_isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.6),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(alignment: Alignment.center, children: [
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: CircularProgressIndicator(
                                  color: Colors.orange[200],
                                  strokeWidth: 4,
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                    color: Colors.orange, strokeWidth: 3),
                              ),
                            ]),
                            const SizedBox(height: 24),
                            const Text('Loading Payment Page…',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            const SizedBox(height: 6),
                            Text('Please wait',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[300])),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Security footer ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.lock_rounded, size: 13, color: Colors.green),
                  const SizedBox(width: 6),
                  Text('Secure SSL Connection',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600])),
                ]),
                const SizedBox(height: 4),
                Text('Payment processed by İşbank',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[600] : Colors.grey[400])),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PAYMENT HEADER  —  mirrors the sticky top bar
// =============================================================================

class _PaymentHeader extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCancel;

  const _PaymentHeader({required this.isDark, required this.onCancel});

  @override
  Widget build(BuildContext context) {
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
                  : Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Cancel / back button
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close_rounded,
                  size: 18,
                  color: isDark ? Colors.grey[400] : Colors.grey[500]),
            ),
          ),
          const SizedBox(width: 12),

          // Lock + title
          const Icon(Icons.lock_rounded, size: 17, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            'Secure Payment',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.grey[900]),
          ),

          const Spacer(),

          // Food order badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.orange.withOpacity(0.15) : Colors.orange[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.restaurant_menu_rounded,
                  size: 13,
                  color: isDark ? Colors.orange[400] : Colors.orange[600]),
              const SizedBox(width: 5),
              Text('Food Order',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.orange[400] : Colors.orange[600])),
            ]),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FULL SCREEN MESSAGE  —  reused for success / failed / missing params states
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
    final bg = isDark ? const Color(0xFF111827) : const Color(0xFFFFFBF5);

    return Scaffold(
      backgroundColor: bg,
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
              Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.grey[900])),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600])),
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
// ORANGE BUTTON  —  reusable primary CTA
// =============================================================================

class _OrangeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OrangeButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }
}

// =============================================================================
// CANCEL DIALOG  —  mirrors confirm(t("cancelPaymentConfirm"))
// =============================================================================

class _CancelDialog extends StatelessWidget {
  final bool isDark;
  const _CancelDialog({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1F2937) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Cancel Payment?',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey[900])),
      content: Text(
        'Your payment is in progress. Are you sure you want to cancel?',
        style: TextStyle(
            fontSize: 14, color: isDark ? Colors.grey[400] : Colors.grey[600]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Continue',
              style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700])),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('Cancel Payment',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
