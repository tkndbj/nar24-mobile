// lib/widgets/market_search_delegate.dart - COMPLETELY AUTH INDEPENDENT

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../generated/l10n/app_localizations.dart';
import '../screens/DYNAMIC-SCREENS/dynamic_category_boxes_screen.dart';
import '../providers/dynamic_category_boxes_provider.dart';
import '../models/suggestion.dart';
import '../providers/market_provider.dart';
import '../providers/search_history_provider.dart';
import '../providers/search_provider.dart';
import '../screens/market_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../models/search_entry.dart';
import 'package:flutter/cupertino.dart';
import '../utils/connectivity_helper.dart';
import '../models/category_suggestion.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/DYNAMIC-SCREENS/market_screen_dynamic_filters_screen.dart';
import '../providers/market_dynamic_filter_provider.dart';
import 'animated_filter_chip.dart';
import '../utils/category_image_mapper.dart';
import '../models/shop_suggestion.dart';

class MarketSearchDelegate extends SearchDelegate<String?> {
  final MarketProvider marketProv;
  final SearchHistoryProvider historyProv;
  final SearchProvider searchProv;
  final AppLocalizations l10n;
    ScrollController? _scrollController;
  static const double _loadMoreThreshold = 200.0;

  MarketSearchDelegate({
    required this.marketProv,
    required this.historyProv,
    required this.searchProv,
    required this.l10n,
  }) : super(
          searchFieldLabel: l10n.searchProducts,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
        );

   ScrollController _getScrollController(BuildContext context) {
    if (_scrollController == null) {
      _scrollController = ScrollController();
      _scrollController!.addListener(() => _onScroll(context));
    }
    return _scrollController!;
  }
  void _onScroll(BuildContext context) {
    if (_scrollController == null) return;
    
    final maxScroll = _scrollController!.position.maxScrollExtent;
    final currentScroll = _scrollController!.position.pixels;
    
    // Check if we're near the bottom
    if (maxScroll - currentScroll <= _loadMoreThreshold) {
      final searchProvider = Provider.of<SearchProvider>(context, listen: false);
      if (searchProvider.hasMoreProducts && !searchProvider.isLoadingMore) {
        searchProvider.loadMoreSuggestions(l10n: l10n);
      }
    }
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? const SystemUiOverlayStyle(
                statusBarBrightness: Brightness.dark,
                statusBarIconBrightness: Brightness.light,
              )
            : const SystemUiOverlayStyle(
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark,
              ),
      ),
      textTheme: theme.textTheme.apply(
        bodyColor: isDark ? Colors.white : Colors.black87,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(
          color: isDark ? Colors.white60 : Colors.grey.shade600,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  void _safelyClearSearchProvider(BuildContext context) {
    try {
      final searchProv = Provider.of<SearchProvider>(context, listen: false);
      if (searchProv.mounted) {
        // Check if not disposed
        searchProv.clear();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SearchProvider already disposed: $e');
      }
    }
  }

  /// Save search term - auth aware but doesn't affect search functionality.
  /// This method is designed to be called fire-and-forget and handles all
  /// errors internally to prevent unhandled exceptions.
  Future<void> _saveSearchTerm(BuildContext context, String searchTerm,
      {bool refreshSuggestions = true}) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final userId = currentUser.uid;
      final now = DateTime.now();
      final placeholderId = UniqueKey().toString();

      historyProv.insertLocalEntry(
        SearchEntry(
          id: placeholderId,
          searchTerm: searchTerm,
          timestamp: now,
          userId: userId,
        ),
      );

      try {
        await FirebaseFirestore.instance.collection('searches').add({
          'userId': userId,
          'searchTerm': searchTerm,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Firebase write failed - rollback the optimistic local entry
        try {
          await historyProv.deleteEntry(placeholderId);
        } catch (_) {
          // Provider may be disposed - ignore rollback failure
        }
        if (kDebugMode) {
          debugPrint('Error saving search term: $e');
        }
      }
    } catch (e) {
      // Catch-all for any unexpected errors (e.g., provider disposed)
      // This ensures fire-and-forget calls never throw unhandled exceptions
      if (kDebugMode) {
        debugPrint('Unexpected error in _saveSearchTerm: $e');
      }
    }
  }

  String _normalizeProductId(String rawId) {
    if (rawId.startsWith('shop_products_')) {
      return rawId.substring('shop_products_'.length);
    } else if (rawId.startsWith('products_')) {
      return rawId.substring('products_'.length);
    }
    return rawId;
  }

  void _dismissKeyboard(BuildContext context) {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.focusedChild!.unfocus();
    }
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use Listener instead of GestureDetector for keyboard dismissal.
    // Listener doesn't participate in the gesture arena, so it won't
    // compete with child widgets like IconButton, ensuring all taps work
    // on the first attempt.
    return Listener(
      onPointerDown: (_) => _dismissKeyboard(context),
      behavior: HitTestBehavior.translucent,
      child: Container(
        color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
        child: Column(
          children: [
            _buildNetworkStatusBanner(context),
            // Dynamic filters section - ALWAYS at top
            _buildDynamicFiltersSection(context, isDark),
            Expanded(
              child: Consumer<SearchProvider>(
                builder: (context, searchProvider, child) {
                  return _buildSuggestionsContent(
                      context, isDark, searchProvider);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build suggestions content based on current state
  Widget _buildSuggestionsContent(
      BuildContext context, bool isDark, SearchProvider searchProvider) {
    // 1. Empty query = show history
    if (query.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('🔍 SearchDelegate: Empty query, showing history');
      }
      return Consumer<SearchHistoryProvider>(
        builder: (ctx, historyProv, _) {
          // Check if we're loading history
          if (historyProv.isLoadingHistory) {
            return _buildLoadingState(ctx, isDark);
          }

          final history = historyProv.searchEntries.take(10).toList();
          if (history.isEmpty) {
            return _buildEmptyState(ctx, isDark);
          }
          return _buildSearchHistory(ctx, isDark, history);
        },
      );
    }

    // 2. Error state
    if (searchProvider.errorMessage != null) {
      if (kDebugMode) {
        debugPrint(
            '🔍 SearchDelegate: Error state - ${searchProvider.errorMessage}');
      }
      return _buildErrorState(context, isDark, searchProvider);
    }

    // 3. Loading state (only if no data)
    final hasData = searchProvider.suggestions.isNotEmpty ||
        searchProvider.categorySuggestions.isNotEmpty ||
        searchProvider.shopSuggestions.isNotEmpty;

    if (searchProvider.isLoading && !hasData) {
      if (kDebugMode) {
        debugPrint('🔍 SearchDelegate: Loading state');
      }
      return _buildLoadingState(context, isDark);
    }

    // 4. Show suggestions
    if (kDebugMode) {
      debugPrint(
          '🔍 SearchDelegate: Showing suggestions - Products: ${searchProvider.suggestions.length}, Categories: ${searchProvider.categorySuggestions.length}');
    }
    return _buildSearchSuggestions(
      context,
      isDark,
      searchProvider.categorySuggestions,
      searchProvider.suggestions,
      searchProvider.shopSuggestions,
      isLoading: searchProvider.isLoading,
    );
  }

  Widget _buildLoadingState(BuildContext context, bool isDark) {
    return Column(
      children: [
        Container(
          height: 3,
          width: double.infinity,
          child: const LinearProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
          ),
        ),
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(
      BuildContext context, bool isDark, SearchProvider searchProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                searchProvider.hasNetworkError
                    ? Icons.wifi_off_rounded
                    : Icons.error_outline_rounded,
                size: 40,
                color: searchProvider.hasNetworkError
                    ? Colors.orange
                    : Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              searchProvider.errorMessage!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await searchProvider.retry(l10n: l10n);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.searchRetryButton),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

 Widget _buildSearchSuggestions(
  BuildContext context,
  bool isDark,
  List<CategorySuggestion> categorySuggestions,
  List<Suggestion> productSuggestions,
  List<ShopSuggestion> shopSuggestions, {
  bool isLoading = false,
}) {
  return CustomScrollView(
    controller: _getScrollController(context), // ADD THIS
    slivers: [
      // Loading indicator at top if still loading
      if (isLoading)
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
            ),
          ),
        ),

      // Shops section (unchanged)
      if (shopSuggestions.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                Icon(
                  Icons.store_rounded,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.shops ?? 'Shops',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${shopSuggestions.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final shop = shopSuggestions[index];
              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromARGB(255, 33, 31, 49)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: Colors.grey.shade200,
                    ),
                    child: shop.profileImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Image.network(
                              shop.profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.store_rounded,
                                  size: 20,
                                  color: Colors.grey.shade600,
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.store_rounded,
                            size: 20,
                            color: Colors.grey.shade600,
                          ),
                  ),
                  title: Text(
                    shop.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    shop.categoriesDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                  onTap: () {
                    _dismissKeyboard(context);
                    final term = query.trim();
                    if (term.isNotEmpty) {
                      _saveSearchTerm(context, term,
                          refreshSuggestions: false);
                    }
                    _safelyClearSearchProvider(context);
                    final marketState =
                        context.findAncestorStateOfType<MarketScreenState>();
                    marketState?.exitSearchMode();
                    context.push('/shop_detail/${shop.id}');
                  },
                ),
              );
            },
            childCount: shopSuggestions.length > 3
                ? 3
                : shopSuggestions.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],

      // Categories section (unchanged)
      if (categorySuggestions.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                Icon(
                  Icons.category_rounded,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.categories,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: categorySuggestions.length,
              itemBuilder: (context, index) {
                final categoryMatch = categorySuggestions[index];
                return _buildCategoryCard(context, isDark, categoryMatch);
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],

      // Products section header
      if (productSuggestions.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_rounded,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.products,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${productSuggestions.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Products list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final suggestion = productSuggestions[index];
              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromARGB(255, 33, 31, 49)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: suggestion.imageUrl != null
                          ? Image.network(
                              suggestion.imageUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.shopping_bag_rounded,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey.shade600,
                                );
                              },
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDark
                                            ? Colors.white30
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Icon(
                              Icons.shopping_bag_rounded,
                              size: 20,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                    ),
                  ),
                  title: Text(
                    suggestion.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    l10n.product,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.north_west_rounded,
                    size: 16,
                    color: isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                  onTap: () {
                    _dismissKeyboard(context);
                    final term = query.trim();
                    if (term.isNotEmpty) {
                      _saveSearchTerm(context, term,
                          refreshSuggestions: false);
                    }
                    _safelyClearSearchProvider(context);
                    final marketState =
                        context.findAncestorStateOfType<MarketScreenState>();
                    marketState?.exitSearchMode();
                    final cleanId = _normalizeProductId(suggestion.id);
                    context.push('/product/$cleanId');
                  },
                ),
              );
            },
            childCount: productSuggestions.length,
          ),
        ),
      ],

      // ADD: Load more indicator at bottom
      SliverToBoxAdapter(
        child: Consumer<SearchProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingMore) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFF6B35),
                      ),
                    ),
                  ),
                ),
              );
            }

            // Show "Load more" hint if there's more to load
            if (provider.hasMoreProducts && productSuggestions.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'Scroll for more',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                  ),
                ),
              );
            }

            return const SizedBox(height: 20);
          },
        ),
      ),

      // No results state (unchanged)
      if (categorySuggestions.isEmpty &&
          productSuggestions.isEmpty &&
          shopSuggestions.isEmpty &&
          !isLoading) ...[
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color.fromARGB(255, 33, 31, 49)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.search_off_rounded,
                      size: 40,
                      color: isDark ? Colors.white30 : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.noResultsFound,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tryDifferentKeywords,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white30 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

  // Helper methods remain the same...
  Widget _buildCategoryCard(
      BuildContext context, bool isDark, CategorySuggestion categoryMatch) {
    String getDisplayName() {
      if (categoryMatch.subsubcategoryKey != null) {
        final parts = categoryMatch.displayName.split(' > ');
        return parts.length >= 3 ? parts[2] : categoryMatch.displayName;
      } else if (categoryMatch.subcategoryKey != null) {
        final parts = categoryMatch.displayName.split(' > ');
        return parts.length >= 2 ? parts[1] : categoryMatch.displayName;
      } else {
        return categoryMatch.displayName;
      }
    }

    String getBreadcrumb() {
      if (categoryMatch.level > 2) {
        // For sub-subcategories: "Main Category • Subcategory"
        final parts = categoryMatch.displayName.split(' > ');
        if (parts.length >= 3) {
          return '${parts[0]} • ${parts[1]}';
        }
      } else if (categoryMatch.level > 1) {
        // For subcategories: "Main Category"
        final parts = categoryMatch.displayName.split(' > ');
        if (parts.length >= 2) {
          return parts[0];
        }
      }
      return '';
    }

    // Get the appropriate image using the new mapper
    final imagePath = CategoryImageMapper.getImagePath(
      categoryMatch.categoryKey,
      subcategoryKey: categoryMatch.subcategoryKey,
    );

    return Container(
      width: 200, // Slightly wider for better text display
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _dismissKeyboard(context);
            final term = query.trim();
            if (term.isNotEmpty) {
              _saveSearchTerm(context, term, refreshSuggestions: false);
            }

            _safelyClearSearchProvider(context);
            final marketState =
                context.findAncestorStateOfType<MarketScreenState>();
            marketState?.exitSearchMode();

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider<CategoryBoxesProvider>(
                  create: (_) => CategoryBoxesProvider(),
                  child: DynamicCategoryBoxesScreen(
                    category: categoryMatch.categoryKey,
                    subcategory: categoryMatch.subcategoryKey,
                    subsubcategory: categoryMatch.subsubcategoryKey,
                    displayName: categoryMatch.displayName,
                  ),
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color:
                  isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.grey.shade200,
              ),
              // Add subtle shadow for better visual hierarchy
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Image section
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: Container(
                    width: 60,
                    height: 70,
                    color: Colors.grey.shade200,
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // Enhanced error handling with category-appropriate fallback icon
                        IconData fallbackIcon;
                        switch (categoryMatch.categoryKey) {
                          case 'Clothing & Fashion':
                            fallbackIcon = Icons.checkroom_rounded;
                            break;
                          case 'Footwear':
                            fallbackIcon = Icons.settings_accessibility_rounded;
                            break;
                          case 'Electronics':
                            fallbackIcon = Icons.devices_rounded;
                            break;
                          case 'Home & Furniture':
                            fallbackIcon = Icons.home_rounded;
                            break;
                          case 'Sports & Outdoor':
                            fallbackIcon = Icons.sports_rounded;
                            break;
                          default:
                            fallbackIcon = Icons.category_rounded;
                        }

                        return Container(
                          color: Colors.grey.shade300,
                          child: Icon(
                            fallbackIcon,
                            color: Colors.grey.shade500,
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Text section
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Main category name
                        Text(
                          getDisplayName(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Breadcrumb for nested categories
                        if (getBreadcrumb().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            getBreadcrumb(),
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? Colors.white30
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatusBanner(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _createConnectivityStream(),
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;
        if (isConnected) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.orange,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                l10n.searchOfflineMode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<bool> _createConnectivityStream() {
    return Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => ConnectivityHelper.isConnected())
        .distinct();
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromARGB(255, 33, 31, 49)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(35),
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 36,
                  color: isDark ? Colors.white30 : Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.noSearchHistory,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.searchProducts,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white30 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicFiltersSection(BuildContext context, bool isDark) {
    return Consumer<DynamicFilterProvider>(
      builder: (context, dynamicFilterProvider, child) {
        if (dynamicFilterProvider.isLoading ||
            dynamicFilterProvider.activeFilters.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12), // Reduced top padding
              SizedBox(
                height: 32, // Much more compact height
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: dynamicFilterProvider.activeFilters.length,
                  itemBuilder: (context, index) {
                    final filter = dynamicFilterProvider.activeFilters[index];
                    final displayName =
                        dynamicFilterProvider.getFilterDisplayName(
                      filter,
                      Localizations.localeOf(context).languageCode,
                    );

                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: AnimatedFilterChip(
                        displayName: displayName,
                        color: _parseColor(filter.color ?? '#FF6B35'),
                        isDark: isDark,
                        onTap: () {
                          _dismissKeyboard(context);
                          _safelyClearSearchProvider(context);
                          final marketState = context
                              .findAncestorStateOfType<MarketScreenState>();
                          marketState?.exitSearchMode();

                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  MarketScreenDynamicFiltersScreen(
                                dynamicFilter: filter,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6), // Reduced bottom padding
            ],
          ),
        );
      },
    );
  }

  Color _parseColor(String colorString) {
    try {
      final cleanColor = colorString.replaceAll('#', '');
      if (cleanColor.length == 6) {
        return Color(int.parse('FF$cleanColor', radix: 16));
      } else if (cleanColor.length == 8) {
        return Color(int.parse(cleanColor, radix: 16));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing color $colorString: $e');
      }
    }
    return const Color(0xFFFF6B35); // Default orange color
  }

  Widget _buildSearchHistory(
      BuildContext context, bool isDark, List<dynamic> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Recent searches header
        Container(
          color: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.recentSearches,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final ok = await showCupertinoDialog<bool>(
                      context: context,
                      builder: (ctx) => CupertinoTheme(
                        data: CupertinoTheme.of(ctx).copyWith(
                          brightness: Theme.of(context).brightness,
                        ),
                        child: CupertinoAlertDialog(
                          title: Text(l10n.clearAll),
                          content: Text(l10n.confirmClearAllSearchHistory),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel),
                            ),
                            CupertinoDialogAction(
                              isDestructiveAction: true,
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.clear),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (ok == true) {
                      try {
                        await historyProv.deleteAllForCurrentUser();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.failedToClearHistory ??
                                  'Failed to clear search history'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: Text(
                    l10n.clearAll,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Search history list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: history.length,
            itemBuilder: (ctx, i) {
              final entry = history[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color.fromARGB(255, 33, 31, 49)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.grey.shade200,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  title: Text(
                    entry.searchTerm,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  trailing: _buildDeleteButton(context, entry, isDark),
                  onTap: () {
                    _dismissKeyboard(context);
                    _saveSearchTerm(context, entry.searchTerm,
                        refreshSuggestions: false);
                    _safelyClearSearchProvider(context);
                    final marketState =
                        context.findAncestorStateOfType<MarketScreenState>();
                    marketState?.exitSearchMode();
                    context.push('/search_results',
                        extra: {'query': entry.searchTerm});
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteButton(BuildContext context, dynamic entry, bool isDark) {
    return Consumer<SearchHistoryProvider>(
      builder: (context, historyProv, child) {
        final isDeleting = historyProv.isDeletingEntry(entry.id);

        // Show loading indicator when deleting
        if (isDeleting) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? Colors.white30 : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          );
        }

        // Use IconButton with explicit constraints for proper Material feedback
        // Removed AnimatedSwitcher which was causing gesture detection issues
        return IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: isDark ? Colors.white30 : Colors.grey.shade400,
          ),
          onPressed: () {
            // Prevent multiple taps by checking if already deleting
            if (!historyProv.isDeletingEntry(entry.id)) {
              _handleDeleteEntry(context, entry.id);
            }
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          splashRadius: 24,
        );
      },
    );
  }

  Future<void> _handleDeleteEntry(BuildContext context, String entryId) async {
    try {
      await historyProv.deleteEntry(entryId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to delete search entry: $e');
      }

      // Show error message to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToDeleteSearchEntry ??
                'Failed to delete search entry'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: l10n.retry ?? 'Retry',
              textColor: Colors.white,
              onPressed: () => _handleDeleteEntry(context, entryId),
            ),
          ),
        );
      }
    }
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [];

  @override
  Widget? buildLeading(BuildContext context) => null;

  @override
  Widget buildResults(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final term = query.trim();

      // Fire-and-forget: Save search term in background without blocking navigation.
      // This prevents UI stutter on lower-end devices while ensuring the search
      // history is still saved reliably. Errors are handled internally.
      if (term.isNotEmpty) {
        _saveSearchTerm(context, term, refreshSuggestions: false);
      }

      _safelyClearSearchProvider(context);
      final marketState = context.findAncestorStateOfType<MarketScreenState>();
      marketState?.exitSearchMode();
      context.push('/search_results', extra: {'query': term});
    });

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1A29)
          : Colors.grey.shade50,
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
        ),
      ),
    );
  }
}
