// lib/routing/routes/restaurant_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/RESTAURANTS/restaurant_shell_screen.dart';
import '../../screens/RESTAURANTS/restaurant_detail_screen.dart';
import '../../screens/CART-FAVORITE/food_cart.dart';
import '../../screens/PAYMENT-RECEIPT/food_checkout_screen.dart';
import '../../screens/PAYMENT-RECEIPT/isbank_food_payment_screen.dart';

class RestaurantRoutes {
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
      GoRoute(
        path: '/restaurants',
        name: 'restaurants',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RestaurantShellScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/restaurant-detail/:id',
        name: 'restaurant-detail',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: RestaurantDetailScreen(
              restaurantId: state.pathParameters['id']!,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
      GoRoute(
        path: '/food-cart',
        name: 'food-cart',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const FoodCartScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/food-checkout',
        name: 'food-checkout',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const FoodCheckoutScreen(),
          transitionsBuilder: _slideTransition,
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
      GoRoute(
        path: '/isbankfoodpayment',
        name: 'isbankfoodpayment',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: state.pageKey,
            child: FoodPaymentScreen(
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
