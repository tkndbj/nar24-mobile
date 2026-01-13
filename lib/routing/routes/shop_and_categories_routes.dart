// lib/routing/routes/shop_and_categories_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Import your providers
import '../../providers/shop_provider.dart';

// Import your screens
import '../../screens/SHOP-SCREENS/shop_screen.dart';
import '../../screens/SHOP-SCREENS/shop_detail_screen.dart';
import '../../screens/CATEGORIES/categories_screen.dart';
import '../../screens/CATEGORIES/categories_teras.dart';
import '../../screens/SHOP-SCREENS/create_shop_screen.dart';

class ShopAndCategoriesRoutes {
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
      // ==================== SHOP SECTION ====================

      // Shop Screen (Browse all shops)
      GoRoute(
        path: '/shop',
        name: 'shop',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider<ShopProvider>(
              create: (_) => ShopProvider(),
              child: const ShopScreen(),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Shop Detail Screen (View specific shop)
      GoRoute(
        path: '/shop_detail/:shopId',
        name: 'shop-detail',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider<ShopProvider>(
              create: (_) => ShopProvider()..initializeData(null, shopId),
              child: ShopDetailScreen(shopId: shopId),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== CATEGORIES SECTION ====================

      // Categories Screen (Main categories view)
      GoRoute(
        path: '/categories',
        name: 'categories',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const CategoriesScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Categories Teras Screen (Special category view)
      GoRoute(
        path: '/categories-teras',
        name: 'categories-teras',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const CategoriesTerasScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/create_shop_screen',
        name: 'create_shop_screen',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const CreateShopScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
