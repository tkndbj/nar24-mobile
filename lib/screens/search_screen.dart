// lib/screens/search_screen.dart - Production Ready Custom Search

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
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../models/search_entry.dart';
import 'package:flutter/cupertino.dart';
import '../utils/connectivity_helper.dart';
import '../models/category_suggestion.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';

class SearchScreen extends StatefulWidget {
  final MarketProvider marketProvider;

  const SearchScreen({
    Key? key,
    required this.marketProvider,
  }) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late TextEditingController _searchController;
  late FocusNode _searchFocusNode;
  late SearchProvider _searchProvider;
  late SearchHistoryProvider _historyProvider;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    // Initialize providers
    _searchProvider = SearchProvider();
    _historyProvider = SearchHistoryProvider();

    // Auto-focus and show keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }
    });

    // Setup search listener
    _searchController.addListener(() {
      final term = _searchController.text.trim();
      _searchProvider.updateTerm(term, l10n: AppLocalizations.of(context));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchProvider.dispose();
    _historyProvider.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.focusedChild!.unfocus();
    }
  }

  Future<void> _saveSearchTerm(String searchTerm) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || searchTerm.trim().isEmpty) return;

    final userId = currentUser.uid;
    final now = DateTime.now();
    final placeholderId = UniqueKey().toString();

    _historyProvider.insertLocalEntry(
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
      await _historyProvider.deleteEntry(placeholderId);
      if (kDebugMode) {
        debugPrint('Error saving search term: $e');
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

  void _submitSearch() {
    final term = _searchController.text.trim();
    if (term.isEmpty) return;

    _dismissKeyboard();
    _saveSearchTerm(term);

    // Navigate to search results
    context.push('/search_results', extra: {'query': term});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SearchProvider>.value(value: _searchProvider),
        ChangeNotifierProvider<SearchHistoryProvider>.value(
            value: _historyProvider),
      ],
      child: GestureDetector(
        onTap: _dismissKeyboard,
        child: Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                FeatherIcons.arrowLeft,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchProducts,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                suffixIcon: IconButton(
                  icon: const Icon(
                    FeatherIcons.search,
                    color: Color(0xFFFF6B35),
                  ),
                  onPressed: _submitSearch,
                ),
              ),
              onSubmitted: (_) => _submitSearch(),
            ),
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
          body: Column(
            children: [
              _buildNetworkStatusBanner(context, l10n),
              Expanded(
                child: Consumer<SearchProvider>(
                  builder: (context, searchProvider, child) {
                    return _buildSuggestionsContent(
                        context, isDark, searchProvider, l10n);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatusBanner(
      BuildContext context, AppLocalizations l10n) {
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

  Widget _buildSuggestionsContent(BuildContext context, bool isDark,
      SearchProvider searchProvider, AppLocalizations l10n) {
    final query = _searchController.text.trim();

    // 1. Empty query = show history
    if (query.isEmpty) {
      return Consumer<SearchHistoryProvider>(
        builder: (ctx, historyProv, _) {
          if (historyProv.isLoadingHistory) {
            return _buildLoadingState(isDark);
          }

          final history = historyProv.searchEntries.take(10).toList();
          if (history.isEmpty) {
            return _buildEmptyState(isDark, l10n);
          }
          return _buildSearchHistory(ctx, isDark, history, l10n);
        },
      );
    }

    // 2. Error state
    if (searchProvider.errorMessage != null) {
      return _buildErrorState(context, isDark, searchProvider, l10n);
    }

    // 3. Loading state (only if no data)
    final hasData = searchProvider.suggestions.isNotEmpty ||
        searchProvider.categorySuggestions.isNotEmpty;

    if (searchProvider.isLoading && !hasData) {
      return _buildLoadingState(isDark);
    }

    // 4. Show suggestions
    return _buildSearchSuggestions(
      context,
      isDark,
      searchProvider.categorySuggestions,
      searchProvider.suggestions,
      l10n,
      isLoading: searchProvider.isLoading,
    );
  }

  Widget _buildLoadingState(bool isDark) {
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

  Widget _buildErrorState(BuildContext context, bool isDark,
      SearchProvider searchProvider, AppLocalizations l10n) {
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

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
    return Center(
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
    );
  }

  Widget _buildSearchHistory(BuildContext context, bool isDark,
      List<dynamic> history, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      await _historyProvider.deleteAllForCurrentUser();
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
                  trailing: Consumer<SearchHistoryProvider>(
                    builder: (context, historyProv, child) {
                      final isDeleting = historyProv.isDeletingEntry(entry.id);

                      return IconButton(
                        icon: isDeleting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDark
                                        ? Colors.white30
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                              ),
                        onPressed: () async {
                          if (!historyProv.isDeletingEntry(entry.id)) {
                            try {
                              await historyProv.deleteEntry(entry.id);
                            } catch (e) {
                              if (kDebugMode) {
                                debugPrint('Failed to delete search entry: $e');
                              }
                            }
                          }
                        },
                      );
                    },
                  ),
                  onTap: () {
                    _dismissKeyboard();
                    _saveSearchTerm(entry.searchTerm);
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

  Widget _buildSearchSuggestions(
    BuildContext context,
    bool isDark,
    List<CategorySuggestion> categorySuggestions,
    List<Suggestion> productSuggestions,
    AppLocalizations l10n, {
    bool isLoading = false,
  }) {
    return CustomScrollView(
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

        // Categories section
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

        // Products section
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.shopping_bag_rounded,
                        size: 20,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
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
                      _dismissKeyboard();
                      final term = _searchController.text.trim();
                      if (term.isNotEmpty) {
                        _saveSearchTerm(term);
                      }
                      final cleanId = _normalizeProductId(suggestion.id);
                      context.push('/product_detail/$cleanId');
                    },
                  ),
                );
              },
              childCount: productSuggestions.length,
            ),
          ),
        ],

        // No results state
        if (categorySuggestions.isEmpty &&
            productSuggestions.isEmpty &&
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

  Widget _buildCategoryCard(
      BuildContext context, bool isDark, CategorySuggestion categoryMatch) {
    String slug(String key) {
      switch (key) {
        case 'Women':
          return 'women';
        case 'Men':
          return 'men';
        case 'Mother & Child':
          return 'child';
        case 'Home & Furniture':
          return 'furniture';
        case 'Cosmetics':
          return 'cosmetic';
        case 'Bags':
          return 'bags';
        case 'Electronics':
          return 'electronics';
        case 'Sports & Outdoor':
          return 'sport';
        case 'Books, Stationery & Hobby':
          return 'hobby';
        default:
          return key
              .toLowerCase()
              .replaceAll('&', 'and')
              .replaceAll(RegExp(r"[ ,]"), '_');
      }
    }

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

    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _dismissKeyboard();
            final term = _searchController.text.trim();
            if (term.isNotEmpty) {
              _saveSearchTerm(term);
            }

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
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  child: Container(
                    width: 50,
                    height: 70,
                    color: Colors.grey.shade200,
                    child: Image.asset(
                      'assets/images/category-boxes/${slug(categoryMatch.categoryKey)}.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade300,
                          child: Icon(
                            Icons.category_rounded,
                            color: Colors.grey.shade500,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                        if (categoryMatch.level > 1) ...[
                          const SizedBox(height: 2),
                          Text(
                            categoryMatch.level == 3
                                ? '${categoryMatch.displayName.split(' > ')[0]} • ${categoryMatch.displayName.split(' > ')[1]}'
                                : categoryMatch.displayName.split(' > ')[0],
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
}
