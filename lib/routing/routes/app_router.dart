// lib/routing/routes/app_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../user_provider.dart';
import '../../route_observer.dart';
import 'general_routes.dart';
import 'auth_routes.dart';
import 'payment_routes.dart';
import 'product_routes.dart';
import 'cargo_routes.dart';
import 'shop_and_categories_routes.dart';
import 'dynamic_routes.dart';
import 'list_product_routes.dart';
import 'profile_routes.dart';
import 'seller_panel_routes.dart';

class AppRouter {
  static GoRouter createRouter({
    required GlobalKey<NavigatorState> navigatorKey,
    required BuildContext context,
  }) {
    return GoRouter(
      navigatorKey: navigatorKey,
      // Re-evaluate redirect when auth state changes (login, logout, email verified, etc.)
      // This is the standard GoRouter pattern for auth-aware routing
      refreshListenable: Provider.of<UserProvider>(context, listen: false),
      initialLocation: '/',
      routes: [
        ...GeneralRoutes.routes,
        ...AuthRoutes.routes,
        ...PaymentRoutes.routes,
        ...ProductRoutes.routes,
        ...CargoRoutes.routes,
        ...ShopAndCategoriesRoutes.routes,
        ...DynamicRoutes.routes,
        ...ListProductRoutes.routes,
        ...ProfileRoutes.routes,
        ...SellerPanelRoutes
            .routes, // ✅ CHANGED: Use .routes instead of .shellRoute
      ],
      redirect: (context, state) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final user = userProvider.user;
        final isLoading = userProvider.isLoading;

        // Don't redirect while loading initial state
        if (isLoading) return null;

        // No user = no auth-related redirects needed
        if (user == null) return null;

        final loc = state.matchedLocation;
        final isLoggingIn = loc == '/login' || loc == '/register';
        final isEmailVerification = loc == '/email-verification';
        final isCargoPanel = loc.startsWith('/cargo');
        final isCompleteName = loc == '/complete-name';

        // ✅ Email verification check (skip for social users)
        final isSocialUser = userProvider.isSocialUser;
        if (!isSocialUser && !user.emailVerified) {
          return isEmailVerification ? null : '/email-verification';
        }

        // ✅ Cargo guy routing
        final isCargoGuy = userProvider.profileData?['cargoGuy'] == true;
        if (isCargoGuy) {
          return isCargoPanel ? null : '/cargo-dashboard';
        } else if (isCargoPanel) {
          return '/';
        }

        // ✅ FIX: Wait for profile state AND name state to be ready
        // This prevents premature redirects during state initialization
        if (!userProvider.isProfileStateReady) {
          return null;
        }

        // ✅ FIX: Also check if name state is ready for Apple users
        // isNameStateReady returns false during saves, preventing redirect loops
        if (userProvider.isAppleUser && !userProvider.isNameStateReady) {
          return null;
        }

        // ✅ FIX: Check if Apple user needs to complete their name
        // needsNameCompletion returns false during saves, preventing redirect loops
        if (!isCompleteName && userProvider.needsNameCompletion) {
          debugPrint('🔀 Router: Redirecting to /complete-name');
          return '/complete-name';
        }

        // ✅ Redirect away from auth screens if already authenticated
        if (isLoggingIn || isEmailVerification) {
          return '/';
        }

        return null;
      },
      errorBuilder: (context, state) => const Scaffold(
        body: Center(child: Text('Page Not Found')),
      ),
      observers: [routeObserver],
    );
  }
}
