// lib/screens/market/market_category_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/market_categories.dart';

const Map<String, String> _kCategoryAssetBySlug = {
  'alcohol-cigarette': 'assets/images/market-items/cigaretteandalcohol.png',
  'snack': 'assets/images/market-items/snacks.png',
  'drinks': 'assets/images/market-items/drinks.png',
  'water': 'assets/images/market-items/water.png',
  'fruit-vegetables': 'assets/images/market-items/vegetablesandfruit.png',
  'food': 'assets/images/market-items/food.png',
  'meat-chicken-fish': 'assets/images/market-items/meat.png',
  'basic-food': 'assets/images/market-items/basicfood.png',
  'dairy-breakfast': 'assets/images/market-items/dairyandbreakfast.png',
  'bakery': 'assets/images/market-items/bakery.png',
  'ice-cream': 'assets/images/market-items/icecream.png',
  'fit-form': 'assets/images/market-items/fitandform.png',
  'home-care': 'assets/images/market-items/homecare.png',
  'home-lite': 'assets/images/market-items/homelite.png',
  'personal-care': 'assets/images/market-items/personalcare.png',
  'technology': 'assets/images/market-items/technology.png',
  'sexual-health': 'assets/images/market-items/sexualhealth.png',
  'baby': 'assets/images/market-items/baby.png',
  'clothing': 'assets/images/market-items/clothing.png',
  'stationery': 'assets/images/market-items/stationery.png',
  'pet': 'assets/images/market-items/pets.png',
  'tools': 'assets/images/market-items/tools.png',
};

// ============================================================================
// SCREEN
// ============================================================================

class MarketCategoryScreen extends StatelessWidget {
  const MarketCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Nar24 Market',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kategoriler',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${kMarketCategories.length} kategori',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Category grid ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final cat = kMarketCategories[index];
                    return _CategoryTile(
                      category: cat,
                      isDark: isDark,
                      onTap: () => context.push(
                        '/market-category/${cat.slug}',
                      ),
                    );
                  },
                  childCount: kMarketCategories.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// CATEGORY TILE
// ============================================================================

class _CategoryTile extends StatelessWidget {
  final MarketCategory category;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: category.color.withOpacity(isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _kCategoryAssetBySlug[category.slug] != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        _kCategoryAssetBySlug[category.slug]!,
                        fit: BoxFit.contain,
                      ),
                    )
                  : Text(category.emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                category.labelTr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
