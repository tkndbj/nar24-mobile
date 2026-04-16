import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/typesense_service.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../models/product_summary.dart';
import '../../models/mock_document_snapshot.dart';
import '../../providers/shop_provider.dart';
import '../../widgets/product_list_sliver.dart';
import '../FILTER-SCREENS/shop_detail_filter_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/cloudinary_image.dart';
import '../../utils/cloudinary_url_builder.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/translation_service.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/productdetail/full_screen_image_viewer.dart';
import 'package:go_router/go_router.dart';

/// Shop Detail Screen - Main entry point.
///
/// Architecture:
/// - Dynamic tabs: Home tab only shown if shop has home images,
///   Collections tab only if the shop has collections.
/// - A single shared header (cover [SliverAppBar], search field, tab bar) is
///   rendered outside the [TabBarView] via [NestedScrollView.headerSliverBuilder].
///   This keeps the cover visually fixed during horizontal tab swipes while
///   still collapsing on vertical scroll.
/// - Each tab's body is a lightweight [CustomScrollView] containing only its
///   body slivers. [AutomaticKeepAliveClientMixin] preserves scroll position
///   and per-tile state (e.g. review translations) across tab switches.
/// - The compound perf issues of the previous NestedScrollView revision
///   (AnimatedBuilder on tabController.animation, heavy selectors in the
///   header, per-tab duplicated header) have been removed.
class ShopDetailScreen extends StatefulWidget {
  final MockDocumentSnapshot? shopDoc;
  final String? shopId;
  final String? preloadedName;
  final double? preloadedRating;

  const ShopDetailScreen({
    super.key,
    this.shopDoc,
    this.shopId,
    this.preloadedName,
    this.preloadedRating,
  });

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _isScrolled = ValueNotifier<bool>(false);

  Timer? _searchDebounce;
  Timer? _loadingTimeout;

  static const Duration _searchDebounceDelay = Duration(milliseconds: 300);
  static const Duration _loadingTimeoutDuration = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController();

    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);

    _initializeShopData();
    _startLoadingTimeout();
  }

  void _initializeShopData() {
    if (widget.shopDoc != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context
              .read<ShopProvider>()
              .initializeData(widget.shopDoc, widget.shopId);
        }
      });
    }
  }

  void _startLoadingTimeout() {
    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(_loadingTimeoutDuration, () {
      if (!mounted) return;
      final provider = context.read<ShopProvider>();
      if (provider.isLoadingShopDoc) {
        provider.setShopDocError(true);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final scrolled = _scrollController.offset > 50;
    if (scrolled != _isScrolled.value) {
      _isScrolled.value = scrolled;
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (!mounted) return;
      context.read<ShopProvider>().filterProductsLocally(
            _searchController.text.trim().toLowerCase(),
          );
    });
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isScrolled.dispose();
    super.dispose();
  }

  void _dismissKeyboard() => _searchFocusNode.unfocus();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Selector<ShopProvider,
          ({bool isLoading, bool hasError, String? shopId})>(
        selector: (_, p) => (
          isLoading: p.isLoadingShopDoc,
          hasError: p.hasShopDocError,
          shopId: p.shopDoc?.id,
        ),
        builder: (context, state, _) {
          final expectedShopId = widget.shopId ?? widget.shopDoc?.id;

          if (state.hasError) {
            return _ErrorView(
              onRetry: () => _handleRetry(context),
            );
          }

          if (state.isLoading ||
              state.shopId != expectedShopId ||
              state.shopId == null) {
            return const _ShimmerLoadingView();
          }

          _loadingTimeout?.cancel();

          return SafeArea(
            top: false,
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: _ShopContentWithTabs(
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                scrollController: _scrollController,
                isScrolled: _isScrolled,
                onDismissKeyboard: _dismissKeyboard,
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleRetry(BuildContext context) {
    final provider = context.read<ShopProvider>();
    provider.setShopDocError(false);
    provider.initializeData(widget.shopDoc, widget.shopId);
    _startLoadingTimeout();
  }
}

/// Immutable configuration that determines tab setup.
/// Used as a key to ensure TabController is recreated when tab count changes.
@immutable
class _TabConfiguration {
  final bool hasHomeImages;
  final bool hasCollections;

  const _TabConfiguration({
    required this.hasHomeImages,
    required this.hasCollections,
  });

  int get tabCount {
    int count = 2; // All Products + Reviews (always present)
    if (hasHomeImages) count++;
    if (hasCollections) count++;
    return count;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TabConfiguration &&
          runtimeType == other.runtimeType &&
          hasHomeImages == other.hasHomeImages &&
          hasCollections == other.hasCollections;

  @override
  int get hashCode => Object.hash(hasHomeImages, hasCollections);
}

/// Determines tab configuration from shop data, then creates tabbed content.
class _ShopContentWithTabs extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ScrollController scrollController;
  final ValueListenable<bool> isScrolled;
  final VoidCallback onDismissKeyboard;

  const _ShopContentWithTabs({
    required this.searchController,
    required this.searchFocusNode,
    required this.scrollController,
    required this.isScrolled,
    required this.onDismissKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ShopProvider, _TabConfiguration>(
      selector: (_, provider) {
        final shopData = provider.shopDoc?.data();
        final homeUrls =
            (shopData?['homeImageUrls'] as List?)?.cast<String>() ?? [];
        final collections = provider.collectionsNotifier.value;
        return _TabConfiguration(
          hasHomeImages: homeUrls.isNotEmpty,
          hasCollections: collections.isNotEmpty,
        );
      },
      builder: (context, tabConfig, _) {
        // ValueKey ensures the TabController is recreated when tab count changes.
        return _TabbedContent(
          key: ValueKey(tabConfig),
          tabConfiguration: tabConfig,
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          scrollController: scrollController,
          isScrolled: isScrolled,
          onDismissKeyboard: onDismissKeyboard,
        );
      },
    );
  }
}

/// Owns the [TabController] and renders the [NestedScrollView] whose header
/// slivers are shared across all tabs.
class _TabbedContent extends StatefulWidget {
  final _TabConfiguration tabConfiguration;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ScrollController scrollController;
  final ValueListenable<bool> isScrolled;
  final VoidCallback onDismissKeyboard;

  const _TabbedContent({
    super.key,
    required this.tabConfiguration,
    required this.searchController,
    required this.searchFocusNode,
    required this.scrollController,
    required this.isScrolled,
    required this.onDismissKeyboard,
  });

  @override
  State<_TabbedContent> createState() => _TabbedContentState();
}

class _TabbedContentState extends State<_TabbedContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tabConfiguration.tabCount,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasHomeTab = widget.tabConfiguration.hasHomeImages;
    final hasCollectionsTab = widget.tabConfiguration.hasCollections;

    return NestedScrollView(
      controller: widget.scrollController,
      headerSliverBuilder: (context, _) => [
        _ShopAppBar(isScrolled: widget.isScrolled),
        SliverToBoxAdapter(
          child: _SearchField(
            controller: widget.searchController,
            focusNode: widget.searchFocusNode,
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            children: [
              _TabBarSection(
                tabController: _tabController,
                hasHomeTab: hasHomeTab,
                hasCollectionsTab: hasCollectionsTab,
              ),
              const Divider(color: Colors.grey, thickness: 1, height: 1),
            ],
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          if (hasHomeTab) const _HomeTab(),
          _ProductsTab(onDismissKeyboard: widget.onDismissKeyboard),
          if (hasCollectionsTab) const _CollectionsTab(),
          const _ReviewsTab(),
        ],
      ),
    );
  }
}

/// Shop App Bar with cover image and shop info.
class _ShopAppBar extends StatelessWidget {
  final ValueListenable<bool> isScrolled;

  const _ShopAppBar({required this.isScrolled});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Selector<ShopProvider, Map<String, dynamic>?>(
      selector: (_, p) => p.shopDoc?.data(),
      builder: (context, shopData, _) {
        if (shopData == null) {
          return _buildShimmerAppBar(context);
        }
        return _buildAppBar(context, shopData, isDark);
      },
    );
  }

  Widget _buildShimmerAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: MediaQuery.sizeOf(context).height * 0.15,
      leading: const _BackButton(iconColor: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(color: Colors.grey),
        ),
      ),
      title: Row(
        children: [
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: const CircleAvatar(radius: 20, backgroundColor: Colors.grey),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(height: 16, width: 100, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(
      BuildContext context, Map<String, dynamic> shopData, bool isDark) {
    final l10n = AppLocalizations.of(context);
    // Prefer storage paths (post-migration), fall back to URLs.
    final coverImageSources = () {
      final paths =
          (shopData['coverImageStoragePaths'] as List?)?.cast<String>();
      if (paths != null && paths.isNotEmpty) return paths;
      return (shopData['coverImageUrls'] as List?)?.cast<String>() ?? <String>[];
    }();
    final profileImageSource =
        (shopData['profileImageStoragePath'] as String?) ??
            (shopData['profileImageUrl'] as String? ?? '');
    final shopName = shopData['name'] ?? l10n.shop;
    final rating = (shopData['averageRating'] as num?)?.toDouble() ?? 0.0;

    return SliverAppBar(
      pinned: true,
      expandedHeight: MediaQuery.sizeOf(context).height * 0.25,
      leading: ValueListenableBuilder<bool>(
        valueListenable: isScrolled,
        builder: (_, scrolled, __) {
          final iconColor =
              isDark ? Colors.white : (scrolled ? Colors.black : Colors.white);
          return _BackButton(iconColor: iconColor);
        },
      ),
      title: Row(
        children: [
          _ShopAvatar(imageSource: profileImageSource),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: isScrolled,
              builder: (_, scrolled, __) {
                final iconColor = isDark
                    ? Colors.white
                    : (scrolled ? Colors.black : Colors.white);
                return Text(
                  shopName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
        ],
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _CoverImage(
          coverImageSources: coverImageSources,
          rating: rating,
        ),
      ),
    );
  }
}

class _ShopAvatar extends StatelessWidget {
  final String imageSource;

  const _ShopAvatar({required this.imageSource});

  @override
  Widget build(BuildContext context) {
    if (imageSource.isEmpty) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey,
        child: Icon(Icons.person, size: 20),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: 40,
        height: 40,
        child: CloudinaryImage.banner(
          source: imageSource,
          cdnWidth: 200,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          useOldImageOnUrlChange: true,
          placeholderBuilder: (_) => Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: const CircleAvatar(radius: 20, backgroundColor: Colors.grey),
          ),
          errorBuilder: (_) => const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey,
            child: Icon(Icons.error, size: 20),
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final List<String> coverImageSources;
  final double rating;

  const _CoverImage({
    required this.coverImageSources,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: coverImageSources.isEmpty
            ? null
            : () => _openFullScreenViewer(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCoverImage(),
            Container(color: Colors.black.withOpacity(0.3)),
            _ShopInfoOverlay(
              rating: rating,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    if (coverImageSources.isEmpty) {
      return Container(color: Colors.grey);
    }

    return CloudinaryImage.banner(
      source: coverImageSources[0],
      cdnWidth: 800,
      fit: BoxFit.cover,
      useOldImageOnUrlChange: true,
      placeholderBuilder: (_) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(color: Colors.grey),
      ),
      errorBuilder: (_) => Container(
        color: Colors.grey,
        child: const Icon(Icons.error),
      ),
    );
  }

  void _openFullScreenViewer(BuildContext context) {
    // For full-screen viewer, resolve URLs for display.
    final urls = coverImageSources.map((source) {
      if (CloudinaryUrl.isStoragePath(source)) {
        return CloudinaryUrl.firebaseStorageUrl(source);
      }
      return source;
    }).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          imageUrls: urls,
          initialIndex: 0,
        ),
      ),
    );
  }
}

class _ShopInfoOverlay extends StatelessWidget {
  final double rating;

  const _ShopInfoOverlay({
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      child: Row(
        children: [
          const Icon(Icons.star, color: Colors.yellow, size: 14),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final Color iconColor;

  const _BackButton({required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: iconColor),
      onPressed: () {
        FocusScope.of(context).unfocus();
        Navigator.of(context).pop();
      },
    );
  }
}

/// Search field.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _SearchField({
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Selector<ShopProvider, bool>(
      selector: (_, p) => p.isSearching,
      builder: (context, isSearching, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              hintText: l10n.searchInStore,
              prefixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, __) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      controller.clear();
                      context.read<ShopProvider>().clearSearch();
                      FocusScope.of(context).unfocus();
                    },
                  );
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF28263B) : Colors.grey[200],
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
        );
      },
    );
  }
}

/// Tab bar section - dynamically shows/hides Home and Collections tabs.
class _TabBarSection extends StatelessWidget {
  final TabController tabController;
  final bool hasHomeTab;
  final bool hasCollectionsTab;

  const _TabBarSection({
    required this.tabController,
    required this.hasHomeTab,
    required this.hasCollectionsTab,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final tabs = [
      if (hasHomeTab) Tab(text: l10n.home2),
      Tab(text: l10n.allProducts),
      if (hasCollectionsTab) Tab(text: l10n.collections),
      Tab(text: l10n.reviews),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabBar = TabBar(
          controller: tabController,
          isScrollable: true,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: tabs,
        );

        return constraints.maxWidth >= 600 ? Center(child: tabBar) : tabBar;
      },
    );
  }
}

/// Filter section - only rendered on the Products tab.
class _FilterSection extends StatelessWidget {
  final VoidCallback onDismissKeyboard;

  const _FilterSection({required this.onDismissKeyboard});

  String _localizedSortLabel(String option, AppLocalizations l10n) {
    switch (option) {
      case 'alphabetical':
        return l10n.alphabetical;
      case 'price_asc':
        return l10n.priceLowToHigh;
      case 'price_desc':
        return l10n.priceHighToLow;
      case 'date':
      default:
        return l10n.date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Selector<ShopProvider, String>(
      selector: (_, p) => p.sortOption,
      builder: (context, sortOption, _) {
        final sortLabel = sortOption != 'date'
            ? _localizedSortLabel(sortOption, l10n)
            : l10n.sort;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _FilterButton(
                  icon: Icons.sort,
                  label: sortLabel,
                  onPressed: () => _showSortOptions(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: _FilterButtonWithBadge(
                      onDismissKeyboard: onDismissKeyboard)),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterButton(
                  icon: Icons.category,
                  label: l10n.category,
                  onPressed: () => _showCategoryOptions(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSortOptions(BuildContext context) {
    onDismissKeyboard();
    final l10n = AppLocalizations.of(context);
    final provider = context.read<ShopProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Sort'),
        actions: [
          _buildSortAction(
              context, l10n.alphabetical, 'alphabetical', provider, isDark),
          _buildSortAction(
              context, l10n.priceLowToHigh, 'price_asc', provider, isDark),
          _buildSortAction(
              context, l10n.priceHighToLow, 'price_desc', provider, isDark),
          _buildSortAction(context, l10n.date, 'date', provider, isDark),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel,
              style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _buildSortAction(
    BuildContext context,
    String label,
    String option,
    ShopProvider provider,
    bool isDark,
  ) {
    return CupertinoActionSheetAction(
      onPressed: () {
        provider.setSortOption(option);
        Navigator.pop(context);
      },
      child: Text(
        label,
        style: TextStyle(
          color: provider.sortOption == option
              ? Colors.orange
              : (isDark ? Colors.white : Colors.black),
        ),
      ),
    );
  }

  void _showCategoryOptions(BuildContext context) {
    onDismissKeyboard();
    final l10n = AppLocalizations.of(context);
    final provider = context.read<ShopProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = provider.getAvailableCategories();

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Category'),
        actions: [
          ...categories.map((category) {
            final displayName =
                provider.getLocalizedCategoryName(category, l10n);
            return CupertinoActionSheetAction(
              onPressed: () {
                provider.setSelectedSubcategory(category);
                Navigator.pop(context);
              },
              child: Text(
                displayName,
                style: TextStyle(
                  color: provider.selectedSubcategory == category
                      ? Colors.orange
                      : (isDark ? Colors.white : Colors.black),
                ),
              ),
            );
          }),
          CupertinoActionSheetAction(
            onPressed: () {
              provider.setSelectedSubcategory(null);
              Navigator.pop(context);
            },
            child: Text(
              l10n.clear,
              style: TextStyle(
                color: provider.selectedSubcategory == null
                    ? Colors.orange
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel,
              style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.orange, size: 20),
      label: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 14,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.grey, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

class _FilterButtonWithBadge extends StatelessWidget {
  final VoidCallback onDismissKeyboard;

  const _FilterButtonWithBadge({required this.onDismissKeyboard});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.read<ShopProvider>();

    return OutlinedButton.icon(
      onPressed: () => _showFilterScreen(context),
      icon: const Icon(Icons.filter_list, color: Colors.orange, size: 20),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.filter,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 14,
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: provider.totalFiltersAppliedNotifier,
            builder: (_, total, __) {
              if (total == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '($total)',
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
                ),
              );
            },
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.grey, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }

  void _showFilterScreen(BuildContext context) {
    onDismissKeyboard();
    final provider = context.read<ShopProvider>();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => ShopDetailFilterScreen(
          shopDoc: provider.shopDoc!,
          initialGender: provider.selectedGender,
          initialBrands: provider.selectedBrands,
          initialTypes: provider.selectedTypes,
          initialFits: provider.selectedFits,
          initialSizes: provider.selectedSizes,
          initialColors: provider.selectedColors,
          initialMinPrice: provider.minPrice,
          initialMaxPrice: provider.maxPrice,
          initialMinRating: provider.minRating,
          availableSpecFacets: provider.facets,
          initialSpecFilters: provider.dynamicSpecFilters,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation),
            child: child,
          );
        },
      ),
    ).then((result) {
      if (result != null) {
        final rawSpecFilters = result['specFilters'];
        final specFilters = <String, List<String>>{};
        if (rawSpecFilters is Map) {
          for (final entry in rawSpecFilters.entries) {
            specFilters[entry.key as String] =
                List<String>.from(entry.value as List);
          }
        }

        provider.updateFilters(
          gender: result['gender'],
          brands: List<String>.from(result['brands'] ?? []),
          types: List<String>.from(result['types'] ?? []),
          fits: List<String>.from(result['fits'] ?? []),
          sizes: List<String>.from(result['sizes'] ?? []),
          colors: List<String>.from(result['colors'] ?? []),
          minPrice: result['minPrice'],
          maxPrice: result['maxPrice'],
          minRating: result['minRating'] as double?,
          totalFilters: result['totalFilters'] ?? 0,
          specFilters: specFilters,
        );
      }
    });
  }
}

// ─── Tabs ─────────────────────────────────────────────────────────────────────

/// Pulls refresh and load-more setup into one place. Each tab wraps its
/// body slivers in a keep-alive scrollable that participates in the
/// [NestedScrollView] coordinator (no explicit ScrollController).
class _TabScrollBody extends StatefulWidget {
  final List<Widget> slivers;
  final double? cacheExtent;
  final NotificationListenerCallback<ScrollNotification>? onScroll;

  const _TabScrollBody({
    required this.slivers,
    this.cacheExtent,
    this.onScroll,
  });

  @override
  State<_TabScrollBody> createState() => _TabScrollBodyState();
}

class _TabScrollBodyState extends State<_TabScrollBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: widget.cacheExtent,
      slivers: widget.slivers,
    );

    final refreshable = RefreshIndicator(
      edgeOffset: 100,
      onRefresh: () => context.read<ShopProvider>().refreshShopDetail(),
      child: scrollView,
    );

    if (widget.onScroll == null) return refreshable;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        widget.onScroll!(n);
        return false;
      },
      child: refreshable,
    );
  }
}

/// Home tab - renders the shop's home images.
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _TabScrollBody(
      slivers: [
        Selector<ShopProvider, List<String>>(
          selector: (_, p) {
            final shopData = p.shopDoc?.data();
            return (shopData?['homeImageUrls'] as List?)?.cast<String>() ?? [];
          },
          builder: (context, homeUrls, _) {
            if (homeUrls.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.home_outlined,
                  message: l10n.noHomeContent ?? 'No home content available',
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _HomeImage(imageUrl: homeUrls[index]),
                childCount: homeUrls.length,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeImage extends StatelessWidget {
  final String imageUrl;

  const _HomeImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final shopData = context.read<ShopProvider>().shopDoc?.data();
    final homeLinks =
        (shopData?['homeImageLinks'] as Map?)?.cast<String, dynamic>() ?? {};

    return GestureDetector(
      onTap: () {
        final linkedProductId = homeLinks[imageUrl] as String?;
        if (linkedProductId != null && linkedProductId.isNotEmpty) {
          context.push('/product/$linkedProductId');
        }
      },
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            Container(height: 200, color: Colors.grey[300]),
        errorWidget: (_, __, ___) => Container(
          height: 200,
          color: Colors.grey[300],
          child: const Icon(Icons.error),
        ),
      ),
    );
  }
}

/// Products tab (All Products). Handles load-more via a [NotificationListener].
class _ProductsTab extends StatelessWidget {
  final VoidCallback onDismissKeyboard;

  const _ProductsTab({required this.onDismissKeyboard});

  bool _handleScroll(ScrollNotification scrollInfo, ShopProvider provider) {
    if (!provider.isLoadingMoreProducts &&
        provider.hasMoreProducts &&
        provider.searchQuery.isEmpty &&
        scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent - 200) {
      provider.loadMoreProducts();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ShopProvider>();

    return ValueListenableBuilder<bool>(
      valueListenable: provider.isLoadingProductsNotifier,
      builder: (context, isLoading, _) {
        return _TabScrollBody(
          cacheExtent: 1000,
          onScroll: (n) => _handleScroll(n, provider),
          slivers: isLoading
              ? const [_ProductShimmerSliver()]
              : _buildProductSlivers(context, provider),
        );
      },
    );
  }

  List<Widget> _buildProductSlivers(
      BuildContext context, ShopProvider provider) {
    final l10n = AppLocalizations.of(context);

    return [
      SliverToBoxAdapter(
        child: _FilterSection(onDismissKeyboard: onDismissKeyboard),
      ),
      // Search results header — independent rebuild scope.
      Selector<ShopProvider, String>(
        selector: (_, p) => p.searchQuery,
        builder: (_, query, __) {
          if (query.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return const SliverToBoxAdapter(child: _SearchResultsHeader());
        },
      ),
      // Filter count row — independent rebuild scope.
      Selector<ShopProvider, int>(
        selector: (_, p) => p.totalFiltersApplied,
        builder: (_, total, __) {
          if (total == 0) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ValueListenableBuilder<int>(
                valueListenable: provider.totalFoundNotifier,
                builder: (_, totalFound, __) {
                  return ValueListenableBuilder<List<ProductSummary>>(
                    valueListenable: provider.allProductSummariesNotifier,
                    builder: (_, summaries, __) {
                      final count =
                          totalFound > 0 ? totalFound : summaries.length;
                      return Text(
                        '$count ${l10n.productsFound}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
      // Products grid.
      ValueListenableBuilder<List<ProductSummary>>(
        valueListenable: provider.allProductSummariesNotifier,
        builder: (context, summaries, _) {
          return Selector<ShopProvider, String?>(
            selector: (_, p) => p.selectedColorForDisplay,
            builder: (context, selectedColor, _) {
              return ProductListSliver(
                products: summaries,
                boostedProducts: const [],
                hasMore: false,
                isLoadingMore: false,
                screenName: 'shop_detail_screen',
                selectedColor: selectedColor,
              );
            },
          );
        },
      ),
      // Load-more spinner — visible only when actively loading more pages.
      ValueListenableBuilder<bool>(
        valueListenable: provider.isLoadingMoreProductsNotifier,
        builder: (context, isLoadingMore, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: provider.hasMoreProductsNotifier,
            builder: (context, hasMore, _) {
              if (!isLoadingMore || !hasMore) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child:
                          CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ];
  }
}

/// Collections tab.
class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _TabScrollBody(
      slivers: [
        Selector<ShopProvider, List<Map<String, dynamic>>>(
          selector: (_, p) => p.collections,
          builder: (context, collections, _) {
            if (collections.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.collections_outlined,
                  message: l10n.noCollections ?? 'No collections available',
                ),
              );
            }

            final shopId = context.read<ShopProvider>().shopDoc?.id ?? '';

            return SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _CollectionCard(
                    collection: collections[index],
                    shopId: shopId,
                  ),
                  childCount: collections.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final Map<String, dynamic> collection;
  final String shopId;

  const _CollectionCard({
    required this.collection,
    required this.shopId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final collectionName = collection['name'] ?? 'Collection';
    final imageUrl = collection['imageUrl'] as String?;
    final collectionId = collection['id'] ?? '';
    final productCount = (collection['productIds'] as List?)?.length ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 39, 36, 57) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: collectionId.isEmpty
              ? null
              : () => context.push('/collection/$collectionId', extra: {
                    'shopId': shopId,
                    'collectionName': collectionName,
                  }),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _CollectionImage(imageUrl: imageUrl, isDark: isDark),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collectionName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$productCount ${productCount == 1 ? "product" : "products"}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: isDark ? Colors.white54 : Colors.grey.shade400,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionImage extends StatelessWidget {
  final String? imageUrl;
  final bool isDark;

  const _CollectionImage({required this.imageUrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildPlaceholder(),
                errorWidget: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Icon(
      Icons.collections_outlined,
      color: isDark ? Colors.white30 : Colors.grey.shade600,
      size: 32,
    );
  }
}

/// Reviews tab. Load-more is triggered via a [NotificationListener] on the
/// body scrollable.
class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab();

  bool _handleScroll(ScrollNotification scrollInfo, ShopProvider provider) {
    if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent - 300 &&
        !provider.isLoadingMoreReviews &&
        provider.hasMoreReviews) {
      provider.loadMoreReviews();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ShopProvider>();
    final l10n = AppLocalizations.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: provider.isLoadingReviewsNotifier,
      builder: (context, isLoading, _) {
        return _TabScrollBody(
          onScroll: (n) => _handleScroll(n, provider),
          slivers: isLoading
              ? const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ]
              : _buildReviewSlivers(context, provider, l10n),
        );
      },
    );
  }

  List<Widget> _buildReviewSlivers(
    BuildContext context,
    ShopProvider provider,
    AppLocalizations l10n,
  ) {
    return [
      Selector<ShopProvider, List<Map<String, dynamic>>>(
        selector: (_, p) => p.reviews,
        builder: (context, reviews, _) {
          if (reviews.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.rate_review_outlined,
                message: l10n.noReviewsYet,
              ),
            );
          }

          final shopId = provider.shopDoc?.id ?? '';

          return SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final review = reviews[index];
                  return _ReviewTile(
                    review: review,
                    shopId: shopId,
                    reviewId: review['id'] ?? '',
                  );
                },
                childCount: reviews.length,
              ),
            ),
          );
        },
      ),
      // Load-more spinner. Backed by a Selector because the provider doesn't
      // expose a dedicated ValueListenable for this flag.
      Selector<ShopProvider, bool>(
        selector: (_, p) => p.isLoadingMoreReviews,
        builder: (_, isLoadingMore, __) {
          if (!isLoadingMore) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        },
      ),
    ];
  }
}

class _ReviewTile extends StatefulWidget {
  final Map<String, dynamic> review;
  final String shopId;
  final String reviewId;

  const _ReviewTile({
    required this.review,
    required this.shopId,
    required this.reviewId,
  });

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  bool _isTranslated = false;
  String _translatedText = '';
  bool _isTranslating = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    final rating = (widget.review['rating'] as num).toDouble();
    final reviewText = widget.review['review'] ?? '';
    final date = _parseTimestamp(widget.review['timestamp']);

    final iconTextColor =
        isDark ? Colors.white : const Color.fromRGBO(0, 0, 0, 0.6);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromARGB(255, 39, 36, 57)
            : const Color.fromARGB(255, 243, 243, 243),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StarRating(rating: rating),
              const SizedBox(width: 4.0),
              Text(
                _formatDate(date),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isTranslating)
            Shimmer.fromColors(
              baseColor: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              highlightColor: isDark ? Colors.grey[500]! : Colors.grey[100]!,
              child: Text(
                reviewText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  backgroundColor:
                      isDark ? Colors.grey[700] : Colors.grey[300],
                ),
              ),
            )
          else
            Text(
              _isTranslated ? _translatedText : reviewText,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap:
                    _isTranslating ? null : () => _translateReview(reviewText),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 14, color: iconTextColor),
                    const SizedBox(width: 4),
                    Text(l10n.translate,
                        style: TextStyle(color: iconTextColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime _parseTimestamp(dynamic timestampValue) {
    if (timestampValue is Timestamp) {
      return timestampValue.toDate();
    } else if (timestampValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestampValue);
    }
    return DateTime.now();
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _translateReview(String originalText) async {
    if (_isTranslating) return;

    if (_isTranslated) {
      setState(() => _isTranslated = false);
      return;
    }

    final userLocale = Localizations.localeOf(context).languageCode;
    final translationService = TranslationService();

    final cachedTranslation =
        translationService.getCached(originalText, userLocale);
    if (cachedTranslation != null) {
      setState(() {
        _translatedText = cachedTranslation;
        _isTranslated = true;
      });
      return;
    }

    setState(() => _isTranslating = true);

    try {
      final translation =
          await translationService.translate(originalText, userLocale);
      if (mounted) {
        setState(() {
          _translatedText = translation;
          _isTranslated = true;
          _isTranslating = false;
        });
      }
    } on RateLimitException catch (e) {
      if (mounted) {
        setState(() => _isTranslating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.retryAfter != null
                ? 'Too many requests. Try again in ${e.retryAfter}s'
                : 'Translation limit reached.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTranslating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error translating review: $e')),
        );
      }
    }
  }
}

class _StarRating extends StatelessWidget {
  final double rating;

  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;
    final emptyStars = 5 - fullStars - (hasHalfStar ? 1 : 0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < fullStars; i++)
          const Icon(FontAwesomeIcons.solidStar, color: Colors.amber, size: 14),
        if (hasHalfStar)
          const Icon(FontAwesomeIcons.starHalfStroke,
              color: Colors.amber, size: 14),
        for (var i = 0; i < emptyStars; i++)
          const Icon(FontAwesomeIcons.star, color: Colors.amber, size: 14),
      ],
    );
  }
}

// ─── Shared building blocks ───────────────────────────────────────────────────

/// Search results header shown above the products list when a query is active.
class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Selector<ShopProvider, ({String query, int count})>(
      selector: (_, p) => (query: p.searchQuery, count: p.allProducts.length),
      builder: (context, state, _) {
        if (state.query.isEmpty) return const SizedBox.shrink();

        final color = isDark ? Colors.tealAccent : Colors.teal;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                l10n.searchResultsCount(state.count.toString()),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Sliver-form products shimmer so the shared header stays visible during
/// product loading.
class _ProductShimmerSliver extends StatelessWidget {
  const _ProductShimmerSliver();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, __) => Shimmer.fromColors(
            baseColor: isDark
                ? const Color.fromARGB(255, 40, 37, 58)
                : Colors.grey[300]!,
            highlightColor: isDark
                ? const Color.fromARGB(255, 60, 57, 78)
                : Colors.grey[100]!,
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 40, 37, 58)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          childCount: 6,
        ),
      ),
    );
  }
}

class _ShimmerLoadingView extends StatelessWidget {
  const _ShimmerLoadingView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Shimmer.fromColors(
        baseColor: isDark
            ? const Color.fromARGB(255, 40, 37, 58)
            : Colors.grey.shade300,
        highlightColor: isDark
            ? const Color.fromARGB(255, 60, 57, 78)
            : Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: kToolbarHeight + MediaQuery.paddingOf(context).top,
              color: isDark
                  ? const Color.fromARGB(255, 40, 37, 58)
                  : Colors.grey.shade300,
            ),
            Container(
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 40, 37, 58)
                    : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Container(
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: isDark
                  ? const Color.fromARGB(255, 40, 37, 58)
                  : Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (_, __) => Container(
                  height: 120,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color.fromARGB(255, 40, 37, 58)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load shop',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
