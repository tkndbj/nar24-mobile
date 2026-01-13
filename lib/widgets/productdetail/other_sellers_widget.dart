import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../screens/SHOP-SCREENS/shop_detail_screen.dart';
import '../../providers/shop_provider.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shimmer/shimmer.dart';

/// Displays other shops selling similar products based on category hierarchy.
/// Uses denormalized category_shops collection for O(1) lookups.
/// Excludes the current shop and caches results for 20 minutes.
class OtherSellersWidget extends StatefulWidget {
  final String productCategory;
  final String productSubcategory;
  final String productSubsubcategory;
  final String currentShopId;

  const OtherSellersWidget({
    Key? key,
    required this.productCategory,
    required this.productSubcategory,
    required this.productSubsubcategory,
    required this.currentShopId,
  }) : super(key: key);

  @override
  _OtherSellersWidgetState createState() => _OtherSellersWidgetState();
}

class _OtherSellersWidgetState extends State<OtherSellersWidget>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<_ShopItemData>> _relatedFuture;

  // Static cache with 20-minute expiry and size limit
  static final Map<String, _CachedShops> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 20);
  static const int _maxCacheSize = 100;

  @override
  void initState() {
    super.initState();
    _relatedFuture = _fetchRelatedShops();
  }

  String _normalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  String get _cacheKey {
    final subSub = _normalize(widget.productSubsubcategory);
    return '${subSub}_${widget.currentShopId}';
  }

  Future<List<_ShopItemData>> _fetchRelatedShops() async {
    // Check cache first
    final cached = _cache[_cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.shops;
    }

    // Clean up cache if too large
    _cleanupCache();

    final firestore = FirebaseFirestore.instance;

    // Normalize category inputs
    final subSub = _normalize(widget.productSubsubcategory);
    final subCat = _normalize(widget.productSubcategory);
    final cat = _normalize(widget.productCategory);

    List<_ShopItemData> shops = [];

    // 1) Try most specific: subsubcategory
    shops = await _fetchFromCategoryDoc(firestore, subSub);

    // 2) Fallback to subcategory
    if (shops.isEmpty) {
      shops = await _fetchFromCategoryDoc(firestore, subCat);
    }

    // 3) Fallback to category
    if (shops.isEmpty) {
      shops = await _fetchFromCategoryDoc(firestore, cat);
    }

    // Filter out current shop and limit to 5
    final filteredShops = shops
        .where((shop) => shop.shopId != widget.currentShopId)
        .take(5)
        .toList();

    // Cache the results
    _cache[_cacheKey] = _CachedShops(
      shops: filteredShops,
      timestamp: DateTime.now(),
    );

    return filteredShops;
  }

  Future<List<_ShopItemData>> _fetchFromCategoryDoc(
    FirebaseFirestore firestore,
    String categoryKey,
  ) async {
    if (categoryKey.isEmpty) return [];

    try {
      final doc = await firestore
          .collection('category_shops')
          .doc(categoryKey)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Category lookup timeout'),
          );

      if (!doc.exists || doc.data() == null) return [];

      final data = doc.data()!;
      final shopsList = data['shops'] as List<dynamic>?;

      if (shopsList == null || shopsList.isEmpty) return [];

      // We need to fetch full shop details since denormalized data only has shopId + shopName
      final shopIds = shopsList
          .map((s) => s['shopId'] as String?)
          .where((id) => id != null && id != widget.currentShopId)
          .take(6) // Get 6 to ensure we have 5 after filtering
          .cast<String>()
          .toList();

      if (shopIds.isEmpty) return [];

      // Fetch full shop details in a single query
      final shopsSnapshot = await firestore
          .collection('shops')
          .where(FieldPath.documentId, whereIn: shopIds)
          .get()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('Shops fetch timeout'),
          );

      return shopsSnapshot.docs
          .where((doc) => doc.id != widget.currentShopId)
          .map((doc) {
            try {
              final data = doc.data();
              return _ShopItemData(
                shopId: doc.id,
                shopName: data['name'] as String? ?? 'Unknown Shop',
                sellerName: data['ownerName'] as String? ?? 'Seller',
                sellerAverageRating:
                    (data['averageRating'] as num?)?.toDouble() ?? 0.0,
                sellerIsVerified: data['verified'] == true,
              );
            } catch (e) {
              print('Error parsing shop data: $e');
              return null;
            }
          })
          .whereType<_ShopItemData>()
          .toList();
    } catch (e) {
      print('Error fetching category shops: $e');
      return [];
    }
  }

  void _cleanupCache() {
    if (_cache.length <= _maxCacheSize) return;

    // Remove expired entries first
    _cache.removeWhere((_, cached) => cached.isExpired);

    // If still too large, remove oldest entries
    if (_cache.length > _maxCacheSize) {
      final sortedEntries = _cache.entries.toList()
        ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));

      final entriesToRemove = sortedEntries.take(_cache.length - _maxCacheSize);
      for (var entry in entriesToRemove) {
        _cache.remove(entry.key);
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);

    return FutureBuilder<List<_ShopItemData>>(
      future: _relatedFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildShimmer(context);
        }
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        final items = snap.data!;
        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color.fromARGB(255, 40, 38, 59)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.checkOtherSellers,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  itemBuilder: (_, idx) => _ShopItem(
                    shopName: items[idx].shopName,
                    sellerName: items[idx].sellerName,
                    sellerAverageRating: items[idx].sellerAverageRating,
                    sellerIsVerified: items[idx].sellerIsVerified,
                    shopId: items[idx].shopId,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmer(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDarkMode ? const Color(0xFF1C1A29) : Colors.grey[300]!;
    final highlightColor = isDarkMode ? const Color.fromARGB(255, 51, 48, 73) : Colors.grey[100]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color.fromARGB(255, 40, 38, 59) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Container(
              width: 150,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                itemBuilder: (_, idx) => Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CachedShops {
  final List<_ShopItemData> shops;
  final DateTime timestamp;

  _CachedShops({
    required this.shops,
    required this.timestamp,
  });

  bool get isExpired {
    return DateTime.now().difference(timestamp) > const Duration(minutes: 20);
  }
}

Route _shopDetailRoute(String shopId) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) {
      return ChangeNotifierProvider<ShopProvider>(
        create: (_) {
          final prov = ShopProvider();
          prov.initializeData(null, shopId);
          return prov;
        },
        child: ShopDetailScreen(shopId: shopId),
      );
    },
    transitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOut));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

class _ShopItemData {
  final String shopId;
  final String shopName;
  final String sellerName;
  final double sellerAverageRating;
  final bool sellerIsVerified;

  _ShopItemData({
    required this.shopId,
    required this.shopName,
    required this.sellerName,
    required this.sellerAverageRating,
    required this.sellerIsVerified,
  });
}

class _ShopItem extends StatefulWidget {
  final String shopName;
  final String sellerName;
  final double sellerAverageRating;
  final bool sellerIsVerified;
  final String shopId;

  const _ShopItem({
    required this.shopName,
    required this.sellerName,
    required this.sellerAverageRating,
    required this.sellerIsVerified,
    required this.shopId,
  });

  @override
  State<_ShopItem> createState() => _ShopItemState();
}

class _ShopItemState extends State<_ShopItem> {
  bool _isNavigating = false;

  Future<void> _incrementShopClickCount() async {
    try {
      final shopRef =
          FirebaseFirestore.instance.collection('shops').doc(widget.shopId);

      await shopRef.update({
        'clickCount': FieldValue.increment(1),
      });

      debugPrint('✅ Incremented clickCount for shop: ${widget.shopId}');
    } catch (e) {
      debugPrint('❌ Error incrementing shop clickCount: $e');
      // Don't block navigation on error
    }
  }

  Future<void> _handleShopNavigation() async {
    // Prevent multiple simultaneous navigations
    if (_isNavigating) {
      debugPrint('⚠️ Navigation already in progress, ignoring tap');
      return;
    }

    if (!mounted) return;

    setState(() {
      _isNavigating = true;
    });

    try {
      // Fire and forget the click count increment (don't wait for it)
      unawaited(_incrementShopClickCount());

      // Navigate immediately
      if (mounted) {
        await Navigator.of(context).push(_shopDetailRoute(widget.shopId));
      }
    } finally {
      // Reset navigation state after navigation completes
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.shopName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.sellerIsVerified) ...[
                const SizedBox(width: 4),
                Image.asset(
                  'assets/images/verify2.png',
                  height: 20,
                  width: 20,
                ),
              ],
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.sellerAverageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _isNavigating ? null : _handleShopNavigation,
              child: Opacity(
                opacity: _isNavigating ? 0.5 : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.goToShop,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper function for fire-and-forget futures
void unawaited(Future<void> future) {
  future.catchError((error) => debugPrint('Unawaited future error: $error'));
}
