// lib/routing/routes/profile_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import your providers
import '../../providers/boost_analysis_provider.dart';
import '../../providers/user_profile_provider.dart';

// Import your screens
import '../../screens/USER-PROFILE/profile_screen.dart';
import '../../screens/USER-PROFILE/settings_screen.dart';
import '../../screens/USER-PROFILE/account_settings_screen.dart';
import '../../screens/USER-PROFILE/complete_profile_screen.dart';
import '../../screens/USER-PROFILE/user_profile_screen.dart';
import '../../screens/USER-PROFILE/addresses_screen.dart';

import '../../screens/USER-PROFILE/two_factor_verification_screen.dart';
import '../../screens/NOTIFICATION-CHAT/notification_screen.dart';
import '../../screens/USER-PROFILE/support_and_faq_screen.dart';
import '../../screens/USER-PROFILE/seller_info_screen.dart';
import '../../screens/USER-PROFILE/my_coupons_and_benefits_screen.dart';

// Import order-related screens
import '../../screens/USER-PROFILE/my_orders_screen.dart';
import '../../screens/USER-PROFILE/refund_order_selection_screen.dart';
import '../../screens/USER-PROFILE/refund_form_screen.dart';
import '../../screens/LOCATION-SCREENS/view_pickup_point_screen.dart';
import '../../screens/USER-PROFILE/archived_products_screen.dart';

// Import product-related screens
import '../../screens/USER-PROFILE/my_products_screen.dart';
import '../../screens/BOOST-SCREENS/boost_screen.dart';
import '../../screens/BOOST-SCREENS/boost_analysis_screen.dart';

import '../../screens/USER-PROFILE/vitrin_pending_product_applications.dart';

class ProfileRoutes {
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
      // ==================== PROFILE SECTION ====================

      // Main Profile Screen
      GoRoute(
        path: '/profile',
        name: 'profile',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ProfileScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Archived Products
      GoRoute(
        path: '/archived-products',
        name: 'archived-products',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ArchivedProductsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // User Profile (view other users)
      GoRoute(
        path: '/user_profile/:userId',
        name: 'user-profile',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider(
              create: (_) => UserProfileProvider(
                FirebaseAuth.instance,
                FirebaseFirestore.instance,
              ),
              child: UserProfileScreen(userId: userId),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Complete Profile
      GoRoute(
        path: '/complete-profile',
        name: 'complete-profile',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const CompleteProfileScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== SETTINGS SECTION ====================

      // General Settings
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const SettingsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/vitrin_pending_applications',
        name: 'vitrin_pending_applications',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const VitrinPendingProductApplications(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Account Settings
      GoRoute(
        path: '/account_settings',
        name: 'account-settings',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const AccountSettingsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Two Factor Verification
      GoRoute(
        path: '/two_factor_verification',
        name: 'two-factor-verification',
        pageBuilder: (context, state) {
          final extra = (state.extra is Map ? state.extra as Map : const {})
              as Map<String, dynamic>;
          final rawType = extra['type'] as String?;
          const allowed = {'setup', 'login', 'disable'};
          final type = allowed.contains(rawType) ? rawType! : 'setup';

          return CustomTransitionPage(
            key: state.pageKey,
            child: TwoFactorVerificationScreen(type: type),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Notifications
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const NotificationScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Support and FAQ
      GoRoute(
        path: '/support_and_faq',
        name: 'support-and-faq',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const SupportAndFaqScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== ADDRESS & PAYMENT SECTION ====================

      // Addresses
      GoRoute(
        path: '/addresses',
        name: 'addresses',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: AddressesScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // View Pickup Points
      GoRoute(
        path: '/view_pickup_points',
        name: 'view-pickup-points',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ViewPickupPointsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== ORDERS SECTION ====================

      // My Orders
      GoRoute(
        path: '/my_orders',
        name: 'my-orders',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const MyOrdersScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Refund Order Selection
      GoRoute(
        path: '/refund-order-selection',
        name: 'refund-order-selection',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const RefundOrderSelectionScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Refund Form
      GoRoute(
        path: '/refund_form',
        name: 'refund-form',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const RefundFormScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== SELLER SECTION ====================

      // Seller Info
      GoRoute(
        path: '/seller_info',
        name: 'seller-info',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const SellerInfoScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // My Coupons and Benefits
      GoRoute(
        path: '/my_coupons_and_benefits',
        name: 'my-coupons-and-benefits',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const MyCouponsAndBenefitsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // My Products
      GoRoute(
        path: '/myproducts',
        name: 'my-products',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const MyProductsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== BOOST SECTION ====================

      GoRoute(
        path: '/boost-product/:productId',
        name: 'boost-product',
        pageBuilder: (context, state) {
          final productId = state.pathParameters['productId'];

          if (productId == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('No product ID provided'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: BoostScreen(
              productId: productId,
              isShopContext: false,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/boost-shop-product/:shopId/:productId',
        name: 'boost-shop-product',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId'];
          final productId = state.pathParameters['productId'];

          if (shopId == null || productId == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Missing shop or product information'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: BoostScreen(
              productId: productId,
              shopId: shopId,
              isShopContext: true,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/boost',
        name: 'boost',
        pageBuilder: (context, state) {
          // Check if there are any optional query parameters
          final shopId = state.uri.queryParameters['shopId'];
          final productId = state.uri.queryParameters['productId'];

          return CustomTransitionPage(
            key: state.pageKey,
            child: BoostScreen(
              productId: productId,
              shopId: shopId,
              isShopContext: shopId != null,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/boost-shop-products/:shopId',
        name: 'boost-shop-products',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId'];

          if (shopId == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Missing shop information'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: BoostScreen(
              shopId: shopId,
              isShopContext: true,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Boost Analysis
      GoRoute(
        path: '/boost-analysis',
        name: 'boost-analysis',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider(
              create: (context) => BoostAnalysisProvider(),
              child: const BoostAnalysisScreen(),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
