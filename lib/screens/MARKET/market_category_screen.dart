// lib/screens/market/market_category_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';

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

class MarketCategoryScreen extends StatefulWidget {
  const MarketCategoryScreen({super.key});

  @override
  State<MarketCategoryScreen> createState() => _MarketCategoryScreenState();
}

class _MarketCategoryScreenState extends State<MarketCategoryScreen>
    with SingleTickerProviderStateMixin {
  static const _kSearchAnimDuration = Duration(milliseconds: 260);

  late final AnimationController _searchAnimCtrl;
  late final Animation<double> _searchAnim;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _searchAnimCtrl = AnimationController(
      vsync: this,
      duration: _kSearchAnimDuration,
    );
    _searchAnim = CurvedAnimation(
      parent: _searchAnimCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _searchAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    setState(() => _searchOpen = true);
    // Forward animation first; request focus after the frame so the field
    // is mounted and focusable.
    await _searchAnimCtrl.forward();
    if (!mounted) return;
    _searchFocus.requestFocus();
  }

  Future<void> _closeSearch() async {
    if (!_searchOpen) return;
    _searchFocus.unfocus();
    await _searchAnimCtrl.reverse();
    if (!mounted) return;
    setState(() {
      _searchOpen = false;
      _searchController.clear();
    });
  }

  void _submitSearch(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _searchFocus.unfocus();
    context.push('/market-search?q=${Uri.encodeQueryComponent(trimmed)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 0,
        title: AnimatedBuilder(
          animation: _searchAnim,
          builder: (context, _) {
            final t = _searchAnim.value;
            return SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.centerLeft,
                fit: StackFit.expand,
                children: [
                  // Title (fades out as search opens)
                  IgnorePointer(
                    ignoring: _searchOpen,
                    child: Opacity(
                      opacity: 1 - t,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.marketCategoryTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Search field (fades/slides in). Mount only when opening.
                  if (_searchOpen)
                    Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(12 * (1 - t), 0),
                        child: _AppBarSearchField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          hintText: l10n.marketSearchHint,
                          onSubmitted: _submitSearch,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_searchOpen ? Icons.arrow_back : Icons.arrow_back),
          onPressed: () {
            if (_searchOpen) {
              _closeSearch();
            } else {
              context.canPop() ? context.pop() : context.go('/');
            }
          },
        ),
        actions: [
          AnimatedBuilder(
            animation: _searchAnim,
            builder: (context, _) {
              final showClose = _searchAnim.value > 0.5;
              return IconButton(
                icon: Icon(showClose ? Icons.close : Icons.search),
                onPressed: _searchOpen ? _closeSearch : _openSearch,
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
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
                      l10n.marketCategoriesHeader,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.marketCategoriesCount(kMarketCategories.length),
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
      ),
    );
  }
}

// ============================================================================
// APPBAR SEARCH FIELD
// ============================================================================

class _AppBarSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  const _AppBarSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        cursorColor: Colors.white,
        cursorHeight: 22,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 15,
          ),
        ),
        onSubmitted: onSubmitted,
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
