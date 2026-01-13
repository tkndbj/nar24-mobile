// lib/widgets/productdetail/product_detail_seller_info.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/product_detail_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/shop_provider.dart';
import '../../screens/SHOP-SCREENS/shop_detail_screen.dart';

class ProductDetailSellerInfo extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  final String? shopId;

  const ProductDetailSellerInfo({
    Key? key,
    required this.sellerId,
    required this.sellerName,
    this.shopId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String? currentUserId = currentUser?.uid;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Selector<ProductDetailProvider, _SellerInfoData>(
      selector: (context, provider) => _SellerInfoData(
        sellerName:
            provider.sellerName.isNotEmpty ? provider.sellerName : sellerName,
        sellerAverageRating: provider.sellerAverageRating,
        shopAverageRating: provider.shopAverageRating,
        sellerIsVerified: provider.sellerIsVerified,
        userId: sellerId,
        currentUserId: currentUserId,
      ),
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, data, child) {
        if (data.userId == null) {
          return const SizedBox.shrink();
        }
        final isShop = shopId != null && shopId!.isNotEmpty;

        final displayName =
            shopId != null && shopId!.isNotEmpty ? sellerName : data.sellerName;
        final displayRating =
            isShop ? data.shopAverageRating : data.sellerAverageRating;
        final canNavigate =
            (shopId != null && shopId!.isNotEmpty) || (sellerId.isNotEmpty);

        // Pre-calculate values that don't need to be in the build tree
        final containerColor = isDarkMode
            ? const Color.fromARGB(255, 39, 36, 57)
            : const Color.fromARGB(255, 243, 243, 243);

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color.fromARGB(255, 40, 38, 59)
                  : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  spreadRadius: 0,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: InkWell(
                    onTap: canNavigate
                        ? () {
                            if (isShop) {
                              // ————————————————
                              // Shop detail: scoped ShopProvider
                              // ————————————————
                              Navigator.of(context).push(
                                PageRouteBuilder(
                                  pageBuilder: (ctx, anim, sec) {
                                    return ChangeNotifierProvider<ShopProvider>(
                                      create: (_) {
                                        final prov = ShopProvider();
                                        prov.initializeData(null, shopId!);
                                        return prov;
                                      },
                                      child: ShopDetailScreen(shopId: shopId!),
                                    );
                                  },
                                  transitionDuration:
                                      const Duration(milliseconds: 200),
                                  transitionsBuilder:
                                      (ctx, animation, sec, child) {
                                    final tween = Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).chain(CurveTween(curve: Curves.easeOut));
                                    return SlideTransition(
                                      position: animation.drive(tween),
                                      child: child,
                                    );
                                  },
                                ),
                              );
                            } else {
                              // ————————————————
                              // Seller reviews: still GoRouter
                              // ————————————————
                              context.push('/seller_reviews/$sellerId');
                            }
                          }
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName
                                    : 'Unknown Seller',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (data.sellerIsVerified) ...[
                              const SizedBox(width: 4),
                              Image.asset(
                                'assets/images/verify2.png',
                                height: 20,
                                width: 20,
                                // Add caching behavior
                                cacheHeight: 20,
                                cacheWidth: 20,
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                displayRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SellerInfoData {
  final String sellerName;
  final double sellerAverageRating;
  final double shopAverageRating;
  final bool sellerIsVerified;
  final String? userId;
  final String? currentUserId;

  const _SellerInfoData({
    required this.sellerName,
    required this.sellerAverageRating,
    required this.shopAverageRating,
    required this.sellerIsVerified,
    required this.userId,
    required this.currentUserId,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _SellerInfoData &&
        other.sellerName == sellerName &&
        other.sellerAverageRating == sellerAverageRating &&
        other.shopAverageRating == shopAverageRating &&
        other.sellerIsVerified == sellerIsVerified &&
        other.userId == userId &&
        other.currentUserId == currentUserId;
  }

  @override
  int get hashCode {
    return Object.hash(
      sellerName,
      sellerAverageRating,
      shopAverageRating,
      sellerIsVerified,
      userId,
      currentUserId,
    );
  }
}
