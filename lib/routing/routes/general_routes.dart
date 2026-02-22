// lib/routing/routes/general_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Import your providers
import '../../providers/search_results_provider.dart';

// Import your services/handlers
import '../../services/deep_link_handler.dart';
import '../../services/typesense_service_manager.dart';

// Import your screens
import '../../screens/market_screen.dart';
import '../../screens/search_results_screen.dart';

class GeneralRoutes {
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
      // ==================== HOME/MARKET ====================

      // Home Screen (Market Screen)
      GoRoute(
        path: '/',
        name: 'home',
        pageBuilder: (context, state) {
          // Check for tab parameter
          final tabParam = state.uri.queryParameters['tab'];
          int? initialTab;
          if (tabParam != null) {
            initialTab = int.tryParse(tabParam);
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: MarketScreen(initialTab: initialTab),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== SEARCH ====================

      // Search Results
      GoRoute(
        path: '/search_results',
        name: 'search-results',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final query = extra['query'] as String? ?? '';

          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider(
              create: (_) => SearchResultsProvider(
                searchService: TypeSenseServiceManager.instance.shopService,
              ),
              child: SearchResultsScreen(query: query),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== DEEP LINKS / SHARED CONTENT ====================

      // Shared Favorites Deep Link
      GoRoute(
        path: '/shared-favorites/:shareId',
        name: 'shared-favorites',
        pageBuilder: (context, state) {
          final shareId = state.pathParameters['shareId']!;

          return CustomTransitionPage(
            key: state.pageKey,
            child: _SharedFavoritesLoader(shareId: shareId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}

// ==================== HELPER WIDGETS ====================

/// Widget to handle shared favorites loading and navigation
class _SharedFavoritesLoader extends StatefulWidget {
  final String shareId;

  const _SharedFavoritesLoader({required this.shareId});

  @override
  State<_SharedFavoritesLoader> createState() => _SharedFavoritesLoaderState();
}

class _SharedFavoritesLoaderState extends State<_SharedFavoritesLoader> {
  @override
  void initState() {
    super.initState();
    _handleSharedFavorites();
  }

  Future<void> _handleSharedFavorites() async {
    // Small delay to ensure widget tree is built
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    try {
      await DeepLinkHandler.handleSharedFavorites(widget.shareId, context);

      if (mounted) {
        // Navigate to main screen with favorites tab selected
        context.pushReplacement('/?tab=2'); // Tab 2 is favorites
      }
    } catch (e) {
      debugPrint('Error handling shared favorites: $e');

      if (mounted) {
        // Show error and redirect to home
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to import favorites'),
            backgroundColor: Colors.red,
          ),
        );
        context.pushReplacement('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(),
            SizedBox(height: 16),
            Text(
              'Importing favorites...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
