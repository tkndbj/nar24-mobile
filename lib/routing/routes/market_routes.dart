// lib/routing/routes/market_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/MARKET/market_shell_screen.dart';
import '../../screens/MARKET/market_category_detail_screen.dart';
import '../../screens/MARKET/market_cart_screen.dart';
import '../../screens/MARKET/market_checkout_screen.dart';
import '../../screens/MARKET/market_order_detail_screen.dart';
import '../../screens/MARKET/market_receipt_detail_screen.dart';
import '../../screens/MARKET/my_market_orders_screen.dart';
import '../../screens/MARKET/isbank_market_payment_screen.dart';

class MarketRoutes {
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
      GoRoute(
        path: '/market',
        name: 'market',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MarketShellScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/market-category/:slug',
        name: 'market-category-detail',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: MarketCategoryDetailScreen(
            categorySlug: state.pathParameters['slug']!,
          ),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/market-cart',
        name: 'market-cart',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MarketCartScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/market-checkout',
        name: 'market-checkout',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MarketCheckoutScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/market-order-detail/:id',
        name: 'market-order-detail',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: MarketOrderDetailScreen(
            orderId: state.pathParameters['id']!,
          ),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/market-receipt/:id',
        name: 'market-receipt-detail',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: MarketReceiptDetailScreen(
            receiptId: state.pathParameters['id']!,
          ),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/my-market-orders',
        name: 'my-market-orders',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MyMarketOrdersScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/isbankmarketpayment',
        name: 'isbankmarketpayment',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: MarketPaymentScreen(
              gatewayUrl: extra['gatewayUrl'] as String,
              orderNumber: extra['orderNumber'] as String,
              paymentParams:
                  Map<String, String>.from(extra['paymentParams'] as Map),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
