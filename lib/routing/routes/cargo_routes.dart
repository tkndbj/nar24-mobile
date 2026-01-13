// lib/routing/routes/cargo_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Import your screens
import '../../screens/CARGO-PANEL/cargo_dashboard.dart';
import '../../screens/CARGO-PANEL/cargo_route.dart';

class CargoRoutes {
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

  // Fade transition for error/fallback cases
  static Widget _fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }

  static List<RouteBase> get routes {
    return [
      // ==================== CARGO DASHBOARD ====================

      // Cargo Dashboard (Main cargo management screen)
      GoRoute(
        path: '/cargo-dashboard',
        name: 'cargo-dashboard',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const CargoDashboard(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== CARGO ROUTE ====================

      // Cargo Route (View and manage delivery route)
      GoRoute(
        path: '/cargo-route',
        name: 'cargo-route',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          // Validate required data
          if (extra == null ||
              extra['orders'] == null ||
              extra['isGatherer'] == null) {
            // Redirect to dashboard if data is missing
            return CustomTransitionPage(
              key: state.pageKey,
              child: const CargoDashboard(),
              transitionsBuilder: _fadeTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: CargoRoute(
              orders: extra['orders'] as List<Map<String, dynamic>>,
              isGatherer: extra['isGatherer'] as bool,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
