// lib/routing/routes/dynamic_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Import your providers
import '../../providers/dynamic_market_provider.dart';

// Import your services
import '../../services/typesense_service_manager.dart';

// Import your models
import '../../models/dynamic_filter.dart';

// Import your screens
import '../../screens/market_screen.dart';
import '../../screens/DYNAMIC-SCREENS/dynamic_market.dart';
import '../../screens/FILTER-SCREENS/dynamic_filter_screen.dart';
import '../../screens/FILTER-SCREENS/dynamic_subcategory_filter_screen.dart';
import '../../screens/DYNAMIC-SCREENS/market_screen_dynamic_filters_screen.dart';
import '../../screens/FILTER-SCREENS/market_screen_dynamic_filters_filter_screen.dart';

class DynamicRoutes {
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
      // ==================== DYNAMIC MARKET ====================

      // Dynamic Market Screen (Category-based browsing)
      GoRoute(
        path: '/dynamic-market',
        name: 'dynamic-market',
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;

          return CustomTransitionPage(
            key: state.pageKey,
            child: (args != null && args.containsKey('subcategory'))
                ? ChangeNotifierProvider(
                    create: (_) => ShopMarketProvider(
                      searchService:
                          TypeSenseServiceManager.instance.shopService,
                    ),
                    child: DynamicMarketScreen(
                      selectedSubcategory: args['subcategory'] as String?,
                      displayName: args['displayName'] as String?,
                      category: args['category'] as String,
                      buyerCategory: args['buyerCategory'] as String?,
                      buyerSubcategory: args['buyerSubcategory'] as String?,
                    ),
                  )
                : const MarketScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== FILTER SCREENS ====================

      // Dynamic Filter Screen (Main filter interface)
      GoRoute(
        path: '/dynamic_filter',
        name: 'dynamic-filter',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          return CustomTransitionPage(
            key: state.pageKey,
            child: DynamicFilterScreen(
              category: extra?['category'] as String? ?? '',
              subcategory: extra?['subcategory'] as String?,
              buyerCategory: extra?['buyerCategory'] as String?,
              initialBrands: extra?['initialBrands'] as List<String>?,
              initialColors: extra?['initialColors'] as List<String>?,
              initialSubSubcategories:
                  extra?['initialSubSubcategories'] as List<String>?,
              initialSpecFilters:
                  extra?['initialSpecFilters'] as Map<String, List<String>>?,
              availableSpecFacets:
                  (extra?['availableSpecFacets'] as Map<String, List<Map<String, dynamic>>>?) ?? const {},
              initialMinPrice: extra?['initialMinPrice'] as double?,
              initialMaxPrice: extra?['initialMaxPrice'] as double?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Dynamic Subcategory Filter Screen
      GoRoute(
        path: '/dynamic_subcategory_filter',
        name: 'dynamic-subcategory-filter',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          if (extra == null ||
              extra['category'] == null ||
              extra['subcategoryId'] == null ||
              extra['subcategoryName'] == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Error: Missing category or subcategory data'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: DynamicSubcategoryFilterScreen(
              category: extra['category'] as String,
              subcategoryId: extra['subcategoryId'] as String,
              subcategoryName: extra['subcategoryName'] as String,
              initialBrand: extra['initialBrand'] as String?,
              initialColors: extra['initialColors'] as List<String>?,
              initialSubsubcategory: extra['initialSubsubcategory'] as String?,
              isGenderFilter:
                  extra['isGenderFilter'] as bool? ?? false, // Add this
              gender: extra['gender'] as String?, // Add this
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== FILTERED PRODUCT VIEWS ====================

      // Dynamic Filter Products Screen (Shows filtered products)
      GoRoute(
        path: '/dynamic-filter-products',
        name: 'dynamic-filter-products',
        pageBuilder: (context, state) {
          final dynamicFilter = state.extra as DynamicFilter?;

          if (dynamicFilter == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Error: No filter data provided'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: MarketScreenDynamicFiltersScreen(
              dynamicFilter: dynamicFilter,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Dynamic Filter Products Filter Screen (Filter refinement)
      GoRoute(
        path: '/dynamic-filter-products-filter',
        name: 'dynamic-filter-products-filter',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          if (extra == null || extra['baseFilter'] == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Error: No base filter provided'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          final baseFilter = extra['baseFilter'] as DynamicFilter;

          return CustomTransitionPage(
            key: state.pageKey,
            child: MarketScreenDynamicFiltersFilterScreen(
              baseFilter: baseFilter,
              initialBrands: extra['initialBrands'] as List<String>?,
              initialColors: extra['initialColors'] as List<String>?,
              initialMinPrice: extra['initialMinPrice'] as double?,
              initialMaxPrice: extra['initialMaxPrice'] as double?,
              initialCategory: extra['initialCategory'] as String?,
              initialSubcategory: extra['initialSubcategory'] as String?,
              initialSubSubcategory: extra['initialSubSubcategory'] as String?,
              initialSpecFilters: extra['initialSpecFilters'] as Map<String, List<String>>?,
              availableSpecFacets: (extra['availableSpecFacets'] as Map<String, List<Map<String, dynamic>>>?) ?? const {},
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
