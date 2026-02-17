// lib/routing/routes/seller_panel_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import your provider
import '../../providers/seller_panel_provider.dart';

// Import your models
import '../../models/product.dart';

// Import your screens
import '../../screens/SELLER-PANEL/seller_panel.dart';
import '../../screens/SELLER-PANEL/seller_panel_campaign_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_edit_campaign_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_discount_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_ads_analytics.dart';
import '../../screens/SELLER-PANEL/ads_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_product_questions.dart';
import '../../screens/SELLER-PANEL/seller_panel_reviews_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_reports_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_shop_settings_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_archived_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_bundle_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_collection_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_product_detail.dart';
import '../../screens/SELLER-PANEL/seller_panel_user_permission.dart';
import '../../screens/SELLER-PANEL/seller_panel_receipts_screen.dart';
import '../../screens/SELLER-PANEL/seller_panel_pending_product_applications.dart';

class SellerPanelRoutes {
  // Custom transition builder to reuse
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
      // ShellRoute with SellerPanelProvider for all provider-dependent screens
      ShellRoute(
        builder: (context, state, child) {
          return ChangeNotifierProvider(
            create: (_) => SellerPanelProvider(
              FirebaseAuth.instance,
              FirebaseFirestore.instance,
            ),
            child: child,
          );
        },
        routes: [
          // Main Seller Panel Screen
          GoRoute(
            path: '/seller-panel',
            name: 'seller-panel',
            pageBuilder: (context, state) {
              final bool isAuthenticated =
                  FirebaseAuth.instance.currentUser != null;

              final int initialTabIndex =
                  int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
              final String? initialShopId = state.uri.queryParameters['shopId'];

              return CustomTransitionPage(
                key: state.pageKey,
                child: isAuthenticated
                    ? SellerPanel(
                        initialTabIndex: initialTabIndex,
                        initialShopId: initialShopId,
                      )
                    : const Scaffold(
                        body: Center(
                          child:
                              Text('Please log in to access the seller panel'),
                        ),
                      ),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Campaign Screen
          GoRoute(
            path: '/seller_panel_campaign_screen',
            name: 'seller-campaign',
            pageBuilder: (context, state) {
              final campaign = state.extra as Map<String, dynamic>?;

              if (campaign == null) {
                return CustomTransitionPage(
                  key: state.pageKey,
                  child: Scaffold(
                    appBar: AppBar(title: const Text('Error')),
                    body: const Center(
                      child: Text('Campaign data not found'),
                    ),
                  ),
                  transitionsBuilder: _slideTransition,
                  transitionDuration: const Duration(milliseconds: 200),
                );
              }

              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelCampaignScreen(campaign: campaign),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Edit Campaign Screen
          GoRoute(
            path: '/seller_panel_edit_campaign_screen',
            name: 'seller-edit-campaign',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;

              if (extra == null) {
                return CustomTransitionPage(
                  key: state.pageKey,
                  child: const Scaffold(
                    body: Center(child: Text('Invalid campaign data')),
                  ),
                  transitionsBuilder: _slideTransition,
                  transitionDuration: const Duration(milliseconds: 200),
                );
              }

              final campaign = extra['campaign'] as Map<String, dynamic>;
              final shopId = extra['shopId'] as String;

              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelEditCampaignScreen(
                  campaign: campaign,
                  shopId: shopId,
                ),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Discount Screen
          GoRoute(
            path: '/seller_panel_discount_screen',
            name: 'seller-discount',
            pageBuilder: (context, state) {
              return CustomTransitionPage(
                key: state.pageKey,
                child: const SellerPanelDiscountScreen(),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          GoRoute(
            path: '/seller_panel_receipts/:shopId',
            name: 'seller-receipts',
            pageBuilder: (context, state) {
              final shopId = state.pathParameters['shopId']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelReceiptsScreen(shopId: shopId),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Ads Analytics Screen
          GoRoute(
            path: '/seller_panel_ads_analytics_screen/:shopId',
            name: 'seller-ads-analytics',
            pageBuilder: (context, state) {
              final shopId = state.pathParameters['shopId']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelAdsAnalytics(shopId: shopId),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Ads Screen
          GoRoute(
            path: '/seller-panel/ads',
            name: 'seller-ads',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;

              if (extra == null) {
                return CustomTransitionPage(
                  key: state.pageKey,
                  child: const Scaffold(
                    body: Center(child: Text('Shop data not found')),
                  ),
                  transitionsBuilder: _slideTransition,
                  transitionDuration: const Duration(milliseconds: 200),
                );
              }

              return CustomTransitionPage(
                key: state.pageKey,
                child: AdsScreen(
                  shopId: extra['shopId'] as String,
                  shopName: extra['shopName'] as String,
                ),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Ads Screen (alternate path)
          GoRoute(
            path: '/seller-panel/ads_screen',
            name: 'ads_screen',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return CustomTransitionPage(
                key: state.pageKey,
                child: AdsScreen(
                  shopId: extra?['shopId'] as String,
                  shopName: extra?['shopName'] as String,
                  initialTabIndex:
                      extra?['initialTabIndex'] as int? ?? 0, // ← ADD
                ),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Shop Settings Screen
          GoRoute(
            path: '/seller_panel_shop_settings/:shopId',
            name: 'seller-shop-settings',
            pageBuilder: (context, state) {
              final shopId = state.pathParameters['shopId']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelShopSettingsScreen(shopId: shopId),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // User Permission Screen
          GoRoute(
            path: '/seller_panel_user_permission/:shopId',
            name: 'seller-user-permission',
            pageBuilder: (context, state) {
              final shopId = state.pathParameters['shopId']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelUserPermission(shopId: shopId),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Archived Screen
          GoRoute(
            path: '/seller_panel_archived_screen',
            name: 'seller-archived',
            pageBuilder: (context, state) {
              return CustomTransitionPage(
                key: state.pageKey,
                child: const SellerPanelArchivedScreen(),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Bundle Screen
          GoRoute(
            path: '/seller_panel_bundle_screen',
            name: 'seller-bundle',
            pageBuilder: (context, state) {
              return CustomTransitionPage(
                key: state.pageKey,
                child: const SellerPanelBundleScreen(),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Collection Management Screen
          GoRoute(
            path: '/seller_panel_collection_screen',
            name: 'seller-collections',
            pageBuilder: (context, state) {
              return CustomTransitionPage(
                key: state.pageKey,
                child: const SellerPanelCollectionScreen(),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),

          // Product Detail Screen
          GoRoute(
            path: '/seller_panel_product_detail',
            name: 'seller-product-detail',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final product = extra?['product'] as Product?;

              if (product == null) {
                return CustomTransitionPage(
                  key: state.pageKey,
                  child: const Scaffold(
                    body: Center(child: Text('Error: Product not found')),
                  ),
                  transitionsBuilder: _slideTransition,
                  transitionDuration: const Duration(milliseconds: 200),
                );
              }

              return CustomTransitionPage(
                key: state.pageKey,
                child: SellerPanelProductDetail(product: product),
                transitionsBuilder: _slideTransition,
                transitionDuration: const Duration(milliseconds: 200),
              );
            },
          ),
        ],
      ),

      // ✅ STANDALONE ROUTES (independent, no provider needed)

      // Product Questions Screen (independent - uses only shopId)
      GoRoute(
        path: '/seller_panel_product_questions/:shopId',
        name: 'seller-product-questions',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SellerPanelProductQuestions(shopId: shopId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/seller_panel_pending_applications/:shopId',
        name: 'seller-pending-product-applications',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SellerPanelPendingProductApplications(shopId: shopId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Reviews Screen (independent - uses only shopId)
      GoRoute(
        path: '/seller_panel_reviews/:shopId',
        name: 'seller-panel-reviews',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SellerPanelReviewsScreen(shopId: shopId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Reports Screen (independent - uses only shopId)
      GoRoute(
        path: '/seller_panel_reports/:shopId',
        name: 'seller-reports',
        pageBuilder: (context, state) {
          final shopId = state.pathParameters['shopId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SellerPanelReportsScreen(shopId: shopId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }

  // Keep this for backward compatibility, but mark as deprecated
  @Deprecated('Use SellerPanelRoutes.routes instead')
  static ShellRoute get shellRoute {
    throw UnimplementedError('Use SellerPanelRoutes.routes instead');
  }
}
