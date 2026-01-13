// lib/routing/routes/payment_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Import your models
import '../../models/product.dart';

// Import your screens
import '../../screens/PAYMENT-RECEIPT/product_payment_success_screen.dart';
import '../../screens/PAYMENT-RECEIPT/receipt_screen.dart';

class PaymentRoutes {
  // Reusable slide transition
  static Widget _slideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    final tween = Tween(begin: begin, end: end)
        .chain(CurveTween(curve: Curves.easeInOut));
    return SlideTransition(
      position: animation.drive(tween),
      child: child,
    );
  }

  static List<RouteBase> get routes {
    return [
      // ==================== PAYMENT SUCCESS ====================

      // Product Payment Success Screen (with product data)
      GoRoute(
        path: '/product_payment_success',
        name: 'product-payment-success',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          // Check if product data is provided
          if (extra != null &&
              extra['product'] != null &&
              extra['productId'] != null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: ProductPaymentSuccessScreen(
                product: extra['product'] as Product,
                productId: extra['productId'] as String,
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          // Fallback to basic success screen
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ProductPaymentSuccessScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== RECEIPTS ====================

      // Receipt Screen (View payment receipts)
      GoRoute(
        path: '/receipts',
        name: 'receipts',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ReceiptScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
