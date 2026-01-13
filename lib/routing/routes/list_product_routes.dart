// lib/routing/routes/list_product_routes.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

// Import your models
import '../../models/product.dart';

// Import your screens
import '../../screens/LIST-PRODUCT/list_product_screen.dart';
import '../../screens/LIST-PRODUCT/list_product_preview_screen.dart';
import '../../screens/LIST-PRODUCT/list_category_screen.dart';
import '../../screens/LIST-PRODUCT/list_brand_screen.dart';
import '../../screens/LIST-PRODUCT/list_product_gender.dart';
import '../../screens/LIST-PRODUCT/list_color_option_screen.dart';
import '../../screens/LIST-PRODUCT/list_clothing_details_screen.dart';
import '../../screens/LIST-PRODUCT/list_product_white_goods.dart';
import '../../screens/LIST-PRODUCT/list_product_computer_components.dart';
import '../../screens/LIST-PRODUCT/list_product_consoles.dart';
import '../../screens/LIST-PRODUCT/list_product_kitchen_appliances.dart';
import '../../screens/LIST-PRODUCT/list_product_footwear_size.dart';
import '../../screens/LIST-PRODUCT/list_product_pant_details.dart';
import '../../screens/LIST-PRODUCT/list_product_jewelry_type.dart';
import '../../screens/LIST-PRODUCT/list_product_jewelry_material.dart';
import '../../screens/LIST-PRODUCT/list_product_curtain_dimension_screen.dart';
import '../../screens/LIST-PRODUCT/list_product_fantasy_wear_screen.dart';
import '../../screens/UTILITY-SCREENS/success_screen.dart';

class ListProductRoutes {
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
      // ==================== MAIN LISTING SCREENS ====================

      // List Product Screen (Personal)
      GoRoute(
        path: '/list_product_screen',
        name: 'list-product',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const ListProductScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // List Product Screen (Seller Panel / Shop Context)
      GoRoute(
        path: '/list-product-shop',
        name: 'list-product-shop',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final shopId = extra?['shopId'] as String?;
          final existingProduct = extra?['existingProduct'] as Product?;
          final isFromArchivedCollection =
              extra?['isFromArchivedCollection'] as bool? ?? false;

          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductScreen(
              shopId: shopId,
              existingProduct: existingProduct,
              isFromArchivedCollection: isFromArchivedCollection,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // List Product Preview
      GoRoute(
        path: '/list_product_preview',
        name: 'list-product-preview',
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;

          if (args == null) {
            return CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(child: Text('Error: No data provided')),
              ),
              transitionsBuilder: _slideTransition,
              transitionDuration: const Duration(milliseconds: 200),
            );
          }

          final product = args['product'] as Product;
          final imageFiles = args['imageFiles'] as List<XFile>;
          final videoFile = args['videoFile'] as XFile?;
          final phone = args['phone'] as String;
          final region = args['region'] as String;
          final address = args['address'] as String;
          final ibanOwnerName = args['ibanOwnerName'] as String;
          final ibanOwnerSurname = args['ibanOwnerSurname'] as String;
          final iban = args['iban'] as String;
          final isEditMode = args['isEditMode'] as bool? ?? false;
          final originalProduct = args['originalProduct'] as Product?;
          final isFromArchivedCollection =
              args['isFromArchivedCollection'] as bool? ?? false; // NEW

          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductPreviewScreen(
              product: product,
              imageFiles: imageFiles,
              videoFile: videoFile,
              phone: phone,
              region: region,
              address: address,
              ibanOwnerName: ibanOwnerName,
              ibanOwnerSurname: ibanOwnerSurname,
              iban: iban,
              isEditMode: isEditMode,
              originalProduct: originalProduct,
              isFromArchivedCollection: isFromArchivedCollection, // NEW
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== CATEGORY & BRAND ====================

      // Select Category
      GoRoute(
        path: '/list_category',
        name: 'list-category',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListCategoryScreen(
              initialCategory: extra?['initialCategory'] as String?,
              initialSubcategory: extra?['initialSubcategory'] as String?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Select Brand
      GoRoute(
        path: '/list_brand',
        name: 'list-brand',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListBrandScreen(
              category: extra?['category'] as String? ?? '',
              subcategory: extra?['subcategory'] as String?,
              subsubcategory: extra?['subsubcategory'] as String?,
              initialBrand: extra?['initialBrand'] as String?,
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== GENERAL ATTRIBUTES ====================

      // Select Gender
      GoRoute(
        path: '/list_gender',
        name: 'list-gender',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductGenderScreen(
              category: extra?['category'] as String?,
              subcategory: extra?['subcategory'] as String?,
              subsubcategory: extra?['subsubcategory'] as String?,
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Select Color
      GoRoute(
        path: '/list_color',
        name: 'list-color',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListColorOptionScreen(
              initialSelectedColors:
                  extra?['initialSelectedColors'] as Map<String, XFile?>?,
              initialColorData: extra?['initialColorData']
                  as Map<String, Map<String, dynamic>>?,
              existingColorImageUrls: extra?['existingColorImageUrls']
                  as Map<String, List<String>>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/success',
        name: 'success',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const SuccessScreen(),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== CLOTHING & FASHION ====================

      // Clothing Details
      GoRoute(
        path: '/list_clothing',
        name: 'list-clothing',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListClothingDetailsScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Pant Details
      GoRoute(
        path: '/list_pant',
        name: 'list-pant',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductPantDetailsScreen(
              category: extra['category'] as String? ?? 'Women',
              initialAttributes:
                  extra['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Footwear Size
      GoRoute(
        path: '/list_footwear',
        name: 'list-footwear',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductFootwearSizeScreen(
              category: extra?['category'] as String? ?? '',
              subcategory: extra?['subcategory'] as String? ?? '',
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/list_fantasy_wear',
        name: 'list_fantasy_wear',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductFantasyWearScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      GoRoute(
        path: '/list_curtain_dimensions',
        name: 'list_curtain_dimensions',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductCurtainDimensionScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== JEWELRY ====================

      // Jewelry Type
      GoRoute(
        path: '/list_jewelry_type',
        name: 'list-jewelry-type',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductJewelryTypeScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Jewelry Material
      GoRoute(
        path: '/list_jewelry_mat',
        name: 'list-jewelry-material',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductJewelryMaterialScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // ==================== ELECTRONICS & APPLIANCES ====================

      // White Goods
      GoRoute(
        path: '/list_white_goods',
        name: 'list-white-goods',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductWhiteGoodsScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Computer Components
      GoRoute(
        path: '/list_computer_components',
        name: 'list-computer-components',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductComputerComponentsScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Consoles
      GoRoute(
        path: '/list_consoles',
        name: 'list-consoles',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductConsolesScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),

      // Kitchen Appliances
      GoRoute(
        path: '/list_kitchen_appliances',
        name: 'list-kitchen-appliances',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: ListProductKitchenAppliancesScreen(
              initialAttributes:
                  extra?['initialAttributes'] as Map<String, dynamic>?,
            ),
            transitionsBuilder: _slideTransition,
            transitionDuration: const Duration(milliseconds: 200),
          );
        },
      ),
    ];
  }
}
