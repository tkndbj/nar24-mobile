// lib/routing/routes/product_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Import your providers
import '../../providers/product_detail_provider.dart';

// Import your repositories
import '../../providers/product_repository.dart';

// Import your models
import '../../models/product.dart';

// Import your screens
import '../../screens/PRODUCT-SCREENS/product_detail_screen.dart';
import '../../screens/REVIEWS-QUESTIONS/seller_review_screen.dart';
import '../../screens/REVIEWS-QUESTIONS/all_questions_screen.dart';
import '../../screens/REVIEWS-QUESTIONS/ask_to_seller_screen.dart';
import '../../screens/REVIEWS-QUESTIONS/my_reviews_screen.dart';
import '../../screens/REVIEWS-QUESTIONS/user_product_questions_screen.dart';
import '../../screens/CART-FAVORITE/favorite_product_screen.dart';
import '../../screens/DYNAMIC-SCREENS/dynamic_subcategory_screen.dart';
import '../../screens/PRODUCT-SCREENS/special_for_you_screen.dart';
import '../../screens/DYNAMIC-SCREENS/dynamic_collection_screen.dart';
import '../../screens/LIST-PRODUCT/list_product_screen.dart';
import '../../providers/review_provider.dart';

class ProductRoutes {
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

  // Fade transition for specific screens
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
      // ==================== PRODUCT DETAIL ====================

        GoRoute(
      path: '/productdetail/:productId',
      redirect: (context, state) {
        final productId = state.pathParameters['productId']!;
        final query = state.uri.queryParameters['collection'] != null
            ? '?collection=${state.uri.queryParameters['collection']}'
            : '';
        debugPrint('🔗 Redirecting /productdetail/$productId to /product/$productId$query');
        return '/product/$productId$query';
      },
    ),

    // Legacy redirect route (for backward compatibility)
    GoRoute(
      path: '/products/:productId',
      redirect: (context, state) {
        final productId = state.pathParameters['productId']!;
        final query = state.uri.queryParameters['collection'] != null
            ? '?collection=${state.uri.queryParameters['collection']}'
            : '';
        return '/product/$productId$query';
      },
    ),

      // Main Product Detail Screen
      GoRoute(
        path: '/product/:productId',
        name: 'product-detail',
        pageBuilder: (context, state) {
          final id = state.pathParameters['productId']!;
          final extras = state.extra;
          Product? product;
          bool fromShare = false;

          // Handle different extra types
          if (extras is Product) {
            product = extras;
          } else if (extras is Map<String, dynamic>) {
            fromShare = extras['fromShare'] == true;
            product = extras['product'] as Product?;
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider(
              create: (_) => ProductDetailProvider(
                productId: id,
                initialProduct: product,
                repository: context.read<ProductRepository>(),
              ),
              child: ProductDetailScreen(
                productId: id,
                fromShare: fromShare,
              ),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Special For You
      GoRoute(
        path: '/special-for-you',
        name: 'special-for-you',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const SpecialForYouScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== PRODUCT EDITING ====================

      // Edit Product (Personal)
      GoRoute(
        path: '/edit-product',
        name: 'edit-product',
        pageBuilder: (context, state) {
          final Product existingProduct = state.extra as Product;

          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductScreen(
              existingProduct: existingProduct,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Edit Product (Shop Context)
      GoRoute(
        path: '/edit-product-shop',
        name: 'edit-product-shop',
        pageBuilder: (context, state) {
          final Map<String, dynamic> data = state.extra as Map<String, dynamic>;
          final Product existingProduct = data['product'] as Product;
          final String? shopId = data['shopId'] as String?;

          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductScreen(
              existingProduct: existingProduct,
              shopId: shopId,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== REVIEWS ====================

      // My Reviews
      GoRoute(
        path: '/my-reviews',
        name: 'my-reviews',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: ChangeNotifierProvider(
              create: (_) => ReviewProvider(),
              child: const MyReviewsScreen(),
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Seller Reviews
      GoRoute(
        path: '/seller_reviews/:sellerId',
        name: 'seller-reviews',
        pageBuilder: (context, state) {
          final sellerId = state.pathParameters['sellerId']!;
          return CustomTransitionPage(
            key: ValueKey('seller-reviews-$sellerId'),
            child: SellerReviewScreen(sellerId: sellerId),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== QUESTIONS ====================

      // All Questions for Product
      GoRoute(
        path: '/allQuestions/:productId/:sellerId/:isShop',
        name: 'allQuestions', // Match the name used in pushNamed
        pageBuilder: (context, state) {
          final productId = state.pathParameters['productId']!;
          final sellerId = state.pathParameters['sellerId']!;
          final isShop = state.pathParameters['isShop'] == 'true';

          return CustomTransitionPage(
            key: state.pageKey,
            child: AllQuestionsScreen(
              productId: productId,
              sellerId: sellerId,
              isShop: isShop,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Ask Question to Seller
      GoRoute(
        path: '/ask_to_seller',
        name: 'ask-to-seller',
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, dynamic>;
          return CustomTransitionPage(
            key: ValueKey('ask-to-seller-${args['productId']}'),
            child: AskToSellerScreen(
              productId: args['productId'] as String,
              sellerId: args['sellerId'] as String,
              isShop: args['isShop'] as bool,
            ),
            transitionsBuilder: _fadeTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // User's Product Questions
      GoRoute(
        path: '/user-product-questions',
        name: 'user-product-questions',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const UserProductQuestionsScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== FAVORITES ====================

      // Favorite Products
      GoRoute(
        path: '/favorite-products',
        name: 'favorite-products',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const FavoritesScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== PRODUCT BROWSING ====================

      // Subcategory Products
      GoRoute(
        path: '/subcategory_products',
        name: 'subcategory-products',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;

          // Only validate that extra exists and has category & subcategoryName
          // subcategoryId can be empty string for gender-based filtering
          if (extra == null ||
              extra['category'] == null ||
              extra['subcategoryName'] == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Error: Missing subcategory data'),
                ),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          return CustomTransitionPage(
            key: state.pageKey,
            child: DynamicSubcategoryScreen(
              category: extra['category'] as String,
              subcategoryId:
                  extra['subcategoryId'] as String? ?? '', // Allow null/empty
              subcategoryName: extra['subcategoryName'] as String,
              gender: extra['gender'] as String?,
              isGenderFilter: extra['isGenderFilter'] as bool? ?? false,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Collection Products
      GoRoute(
        path: '/collection/:collectionId',
        name: 'collection',
        pageBuilder: (context, state) {
          final collectionId = state.pathParameters['collectionId']!;
          final extra = state.extra as Map<String, dynamic>?;

          return CustomTransitionPage(
            key: state.pageKey,
            child: DynamicCollectionScreen(
              collectionId: collectionId,
              shopId: extra?['shopId'] ?? '',
              collectionName: extra?['collectionName'],
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
