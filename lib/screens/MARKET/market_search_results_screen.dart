// lib/screens/market/market_search_results_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../constants/market_categories.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/market_cart_provider.dart';
import '../../services/market_typesense_service.dart';
import '../../services/typesense_service_manager.dart';
import 'market_category_detail_screen.dart' show MarketItemCard;

class MarketSearchResultsScreen extends StatefulWidget {
  final String initialQuery;

  const MarketSearchResultsScreen({super.key, required this.initialQuery});

  @override
  State<MarketSearchResultsScreen> createState() =>
      _MarketSearchResultsScreenState();
}

class _MarketSearchResultsScreenState extends State<MarketSearchResultsScreen> {
  static const _kPageSize = 20;

  late final MarketTypesenseService _typesense;
  late final TextEditingController _queryController;
  final _scrollController = ScrollController();

  List<MarketItem> _items = [];
  MarketGlobalFacets _facets = MarketGlobalFacets.empty;

  final Set<String> _selectedBrands = {};
  final Set<String> _selectedTypes = {};
  final Set<String> _selectedCategories = {};
  MarketSortOption _sort = MarketSortOption.newest;

  String _query = '';
  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _typesense = TypeSenseServiceManager.instance.marketService;
    _query = widget.initialQuery.trim();
    _queryController = TextEditingController(text: _query);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _initialLoad() async {
    setState(() {
      _isLoading = true;
      _items = [];
      _page = 0;
      _hasMore = true;
    });
    final seq = ++_requestSeq;
    final results = await Future.wait([
      _typesense.searchItemsGlobal(
        query: _query,
        sort: _sort,
        page: 0,
        hitsPerPage: _kPageSize,
        brands: _selectedBrands.isEmpty ? null : _selectedBrands.toList(),
        types: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
        categories:
            _selectedCategories.isEmpty ? null : _selectedCategories.toList(),
      ),
      _typesense.fetchFacetsGlobal(
        query: _query,
        selectedBrands:
            _selectedBrands.isEmpty ? null : _selectedBrands.toList(),
        selectedTypes: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
        selectedCategories:
            _selectedCategories.isEmpty ? null : _selectedCategories.toList(),
      ),
    ]);

    if (!mounted || seq != _requestSeq) return;
    final page = results[0] as MarketSearchPage;
    final facets = results[1] as MarketGlobalFacets;
    setState(() {
      _items = page.items;
      _facets = facets;
      _page = page.page;
      _hasMore = page.items.length >= _kPageSize && page.page + 1 < page.nbPages;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    final seq = _requestSeq;
    final next = _page + 1;
    final page = await _typesense.searchItemsGlobal(
      query: _query,
      sort: _sort,
      page: next,
      hitsPerPage: _kPageSize,
      brands: _selectedBrands.isEmpty ? null : _selectedBrands.toList(),
      types: _selectedTypes.isEmpty ? null : _selectedTypes.toList(),
      categories:
          _selectedCategories.isEmpty ? null : _selectedCategories.toList(),
    );
    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _items.addAll(page.items);
      _page = page.page;
      _hasMore =
          page.items.length >= _kPageSize && page.page + 1 < page.nbPages;
      _isLoadingMore = false;
    });
  }

  void _submitQuery(String value) {
    final trimmed = value.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    _initialLoad();
  }

  void _toggleBrand(String value) {
    setState(() {
      if (!_selectedBrands.add(value)) _selectedBrands.remove(value);
    });
    _initialLoad();
  }

  void _toggleType(String value) {
    setState(() {
      if (!_selectedTypes.add(value)) _selectedTypes.remove(value);
    });
    _initialLoad();
  }

  void _toggleCategory(String value) {
    setState(() {
      if (!_selectedCategories.add(value)) _selectedCategories.remove(value);
    });
    _initialLoad();
  }

  void _clearFilters() {
    if (_selectedBrands.isEmpty &&
        _selectedTypes.isEmpty &&
        _selectedCategories.isEmpty) return;
    setState(() {
      _selectedBrands.clear();
      _selectedTypes.clear();
      _selectedCategories.clear();
    });
    _initialLoad();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final hasFilters = _selectedBrands.isNotEmpty ||
        _selectedTypes.isNotEmpty ||
        _selectedCategories.isNotEmpty;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: _SearchField(
          controller: _queryController,
          hintText: l10n.marketSearchHint,
          onSubmitted: _submitQuery,
        ),
      ),
      body: Column(
        children: [
          _FacetChipsBar(
            facets: _facets,
            selectedBrands: _selectedBrands,
            selectedTypes: _selectedTypes,
            selectedCategories: _selectedCategories,
            onToggleBrand: _toggleBrand,
            onToggleType: _toggleType,
            onToggleCategory: _toggleCategory,
            onClear: hasFilters ? _clearFilters : null,
            l10n: l10n,
            isDark: isDark,
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF00A86B)),
                    ),
                  )
                : _items.isEmpty
                    ? _EmptyState(l10n: l10n, isDark: isDark)
                    : _buildGrid(isDark),
          ),
        ],
      ),
      floatingActionButton: Consumer<MarketCartProvider>(
        builder: (context, cart, _) {
          if (cart.itemCount == 0) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => context.push('/market-cart'),
            backgroundColor: const Color(0xFF00A86B),
            icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white),
            label: Text(
              '${l10n.marketCartItemCount(cart.itemCount)} • ${cart.totals.subtotal.toStringAsFixed(0)} TL',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(bool isDark) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.56,
      ),
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF00A86B)),
              ),
            ),
          );
        }
        return MarketItemCard(item: _items[index], isDark: isDark);
      },
    );
  }
}

// ============================================================================
// SEARCH FIELD (appbar)
// ============================================================================

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        autofocus: false,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 15,
          ),
          icon: const Icon(Icons.search, color: Colors.white, size: 20),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

// ============================================================================
// FACET CHIPS BAR
// ============================================================================

class _FacetChipsBar extends StatelessWidget {
  final MarketGlobalFacets facets;
  final Set<String> selectedBrands;
  final Set<String> selectedTypes;
  final Set<String> selectedCategories;
  final ValueChanged<String> onToggleBrand;
  final ValueChanged<String> onToggleType;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback? onClear;
  final AppLocalizations l10n;
  final bool isDark;

  const _FacetChipsBar({
    required this.facets,
    required this.selectedBrands,
    required this.selectedTypes,
    required this.selectedCategories,
    required this.onToggleBrand,
    required this.onToggleType,
    required this.onToggleCategory,
    required this.onClear,
    required this.l10n,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasAny = facets.brands.isNotEmpty ||
        facets.types.isNotEmpty ||
        facets.categories.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();

    final sections = <Widget>[];
    if (facets.categories.isNotEmpty) {
      sections.add(_section(
        title: l10n.marketCategoriesHeader,
        values: facets.categories,
        selected: selectedCategories,
        onToggle: onToggleCategory,
        labelFormatter: (slug) =>
            kMarketCategoryMap[slug]?.labelTr ?? slug,
      ));
    }
    if (facets.brands.isNotEmpty) {
      sections.add(_section(
        title: l10n.marketFacetBrand,
        values: facets.brands,
        selected: selectedBrands,
        onToggle: onToggleBrand,
      ));
    }
    if (facets.types.isNotEmpty) {
      sections.add(_section(
        title: l10n.marketFacetType,
        values: facets.types,
        selected: selectedTypes,
        onToggle: onToggleType,
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onClear != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear, size: 14),
                  label: Text(l10n.marketClearFilters),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00A86B),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          ...sections,
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required List<MarketFacetValue> values,
    required Set<String> selected,
    required ValueChanged<String> onToggle,
    String Function(String)? labelFormatter,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final fv = values[i];
                final isSelected = selected.contains(fv.value);
                final label = labelFormatter != null
                    ? labelFormatter(fv.value)
                    : fv.value;
                return FilterChip(
                  label: Text('$label (${fv.count})'),
                  selected: isSelected,
                  onSelected: (_) => onToggle(fv.value),
                  selectedColor:
                      const Color(0xFF00A86B).withOpacity(0.18),
                  checkmarkColor: const Color(0xFF00A86B),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF00A86B)
                        : (isDark ? Colors.grey[300] : Colors.grey[800]),
                  ),
                  backgroundColor:
                      isDark ? const Color(0xFF1C1A29) : Colors.grey[100],
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF00A86B)
                        : (isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDark;

  const _EmptyState({required this.l10n, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off,
              size: 64, color: isDark ? Colors.grey[600] : Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            l10n.marketNoProductsFound,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
