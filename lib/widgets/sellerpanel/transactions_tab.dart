import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/seller_panel_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/product_card_4.dart';
import 'dart:async';
import '../../services/typesense_service_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../screens/SELLER-PANEL/seller_panel_order_details_screen.dart';
import '../../utils/attribute_localization_utils.dart';
import 'package:intl/intl.dart';

class TransactionsTab extends StatefulWidget {
  const TransactionsTab({Key? key}) : super(key: key);

  @override
  _TransactionsTabState createState() => _TransactionsTabState();
}

class CategorizedShopTransactions {
  final String date;
  final List<BuyerGroup> buyerGroups;

  CategorizedShopTransactions({
    required this.date,
    required this.buyerGroups,
  });
}

class BuyerGroup {
  final String buyerId;
  final String buyerName;
  final List<DocumentSnapshot> transactions;

  BuyerGroup({
    required this.buyerId,
    required this.buyerName,
    required this.transactions,
  });
}

class _TransactionsTabState extends State<TransactionsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _throttle;
  // Search state
  bool _isSearchMode = false;
  bool _isSearching = false;
  bool _isLoadingMoreSearchResults = false;
  List<DocumentSnapshot> _searchResults = [];
  List<Map<String, dynamic>> _currentSearchResults = [];
  int _currentSearchPage = 0;
  bool _hasMoreSearchResults = true;
  String _lastSearchQuery = '';

  // ✅ OPTIMIZATION: Memoization cache for transaction categorization
  List<DocumentSnapshot>? _lastCategorizedInput;
  List<CategorizedShopTransactions>? _memoizedCategorizedResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);

      // Only fetch if transactions not already loaded
      if (provider.transactions.isEmpty && !provider.isLoadingTransactions) {
        provider.fetchTransactions(
          shopId: provider.selectedShop?.id,
        );
      }

      // Always refresh total sales when tab opens (if shop is selected)
      if (provider.selectedShop != null) {
        provider.refreshTotalSales();
      }
    });
    _setupScrollListener();
    _searchController.addListener(_onSearchChanged);
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_throttle?.isActive ?? false) return;
      _throttle = Timer(const Duration(milliseconds: 200), _tryLoadMore);
    });
  }

  void _tryLoadMore() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent * 0.8) {
      final provider = Provider.of<SellerPanelProvider>(context, listen: false);

      if (_isSearchMode) {
        if (!_isLoadingMoreSearchResults && _hasMoreSearchResults) {
          _loadMoreSearchResults();
        }
      } else {
        if (!provider.isFetchingMoreTransactions &&
            provider.hasMoreTransactions) {
          provider.fetchMoreTransactions(shopId: provider.selectedShop?.id);
        }
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    // Immediate UI feedback
    if (query.isNotEmpty && !_isSearchMode) {
      // ADD MOUNTED CHECK HERE
      if (!mounted) return;
      setState(() {
        _isSearchMode = true;
      });
    } else if (query.isEmpty && _isSearchMode) {
      // ADD MOUNTED CHECK HERE
      if (!mounted) return;
      setState(() {
        _isSearchMode = false;
        _searchResults = [];
        _currentSearchResults = [];
        _isSearching = false;
        _isLoadingMoreSearchResults = false;
        _lastSearchQuery = '';
        _currentSearchPage = 0;
        _hasMoreSearchResults = true;
      });
    }

    // Debounced search execution
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        // This check is already there, good!
        if (query.isNotEmpty) {
          _performTypesenseSearch(query);
        } else {
          // Use the regular transaction search from the provider
          Provider.of<SellerPanelProvider>(context, listen: false)
              .setTransactionSearchQuery('');
        }
      }
    });
  }

  Future<void> _performTypesenseSearch(String query) async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final selectedShop = provider.selectedShop;

    if (selectedShop == null) {
      debugPrint('No selected shop for search');
      return;
    }

    if (query == _lastSearchQuery && _isSearchMode) return;

    if (!mounted) return;

    setState(() {
      _isSearching = true;
      _lastSearchQuery = query;
      _currentSearchPage = 0;
      _hasMoreSearchResults = true;
    });

    try {
      final results = await TypeSenseServiceManager.instance.ordersService
          .searchOrdersByShopId(
        query: query,
        shopId: selectedShop.id,
        page: 0,
        hitsPerPage: 20,
      );

      // Convert results to DocumentSnapshot objects by fetching from Firestore
      final documentSnapshots = await TypeSenseServiceManager
          .instance.ordersService
          .fetchDocumentSnapshotsFromTypeSenseResults(results);

      if (!mounted) return;

      setState(() {
        _currentSearchResults = results;
        _searchResults = documentSnapshots;
        _hasMoreSearchResults = results.length == 20;
        _isSearching = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Orders search error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (!mounted) return;

      setState(() {
        _searchResults = [];
        _hasMoreSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _loadMoreSearchResults() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final selectedShop = provider.selectedShop;

    if (selectedShop == null ||
        !_hasMoreSearchResults ||
        _isLoadingMoreSearchResults ||
        !_isSearchMode) {
      return;
    }

    // ADD MOUNTED CHECK HERE
    if (!mounted) return;

    setState(() {
      _isLoadingMoreSearchResults = true;
      _currentSearchPage++;
    });

    try {
      final results = await TypeSenseServiceManager.instance.ordersService
          .searchOrdersByShopId(
        query: _lastSearchQuery,
        shopId: selectedShop.id,
        page: _currentSearchPage,
        hitsPerPage: 20,
      );

      final newDocumentSnapshots = await TypeSenseServiceManager
          .instance.ordersService
          .fetchDocumentSnapshotsFromTypeSenseResults(results);

      // ADD MOUNTED CHECK HERE BEFORE setState
      if (!mounted) return;

      setState(() {
        _currentSearchResults.addAll(results);
        _searchResults.addAll(newDocumentSnapshots);
        _hasMoreSearchResults = results.length == 20;
        _isLoadingMoreSearchResults = false;
      });
    } catch (e) {
      debugPrint('Load more search results error: $e');

      // ADD MOUNTED CHECK HERE BEFORE setState
      if (!mounted) return;

      setState(() {
        _hasMoreSearchResults = false;
        _isLoadingMoreSearchResults = false;
      });
    }
  }

  List<CategorizedShopTransactions> _categorizeTransactions(
      List<DocumentSnapshot> transactions) {
    // OPTIMIZATION: Fast memoization check - O(1) instead of O(n)
    // Compare length + first/last IDs which covers most real-world cases
    if (_lastCategorizedInput != null &&
        _memoizedCategorizedResult != null &&
        _lastCategorizedInput!.length == transactions.length &&
        transactions.isNotEmpty) {
      final sameFirst =
          _lastCategorizedInput!.first.id == transactions.first.id;
      final sameLast = _lastCategorizedInput!.last.id == transactions.last.id;
      if (sameFirst && sameLast) {
        return _memoizedCategorizedResult!;
      }
    } else if (_lastCategorizedInput != null &&
        _memoizedCategorizedResult != null &&
        transactions.isEmpty &&
        _lastCategorizedInput!.isEmpty) {
      return _memoizedCategorizedResult!;
    }

    // Group by date first
    final Map<String, List<DocumentSnapshot>> dateGroups = {};
    final DateFormat dateFormatter = DateFormat('dd/MM/yyyy');

    for (final transactionDoc in transactions) {
      final data = transactionDoc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] is Timestamp
          ? data['timestamp'] as Timestamp
          : null;

      if (timestamp != null) {
        final date = timestamp.toDate();
        final dateKey = dateFormatter.format(date);

        if (!dateGroups.containsKey(dateKey)) {
          dateGroups[dateKey] = [];
        }
        dateGroups[dateKey]!.add(transactionDoc);
      }
    }

    // Sort dates in descending order (newest first)
    final sortedDates = dateGroups.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('dd/MM/yyyy').parse(a);
        final dateB = DateFormat('dd/MM/yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    final List<CategorizedShopTransactions> result = [];

    for (final dateKey in sortedDates) {
      final dateTransactions = dateGroups[dateKey]!;

      // Group by buyer within each date
      final Map<String, List<DocumentSnapshot>> buyerGroups = {};

      for (final transactionDoc in dateTransactions) {
        final data = transactionDoc.data() as Map<String, dynamic>;
        final buyerId = data['buyerId'] as String? ?? 'unknown';
        final buyerName = data['buyerName'] as String? ?? 'Unknown Buyer';

        final buyerKey =
            '$buyerId|$buyerName'; // Use both ID and name for uniqueness

        if (!buyerGroups.containsKey(buyerKey)) {
          buyerGroups[buyerKey] = [];
        }
        buyerGroups[buyerKey]!.add(transactionDoc);
      }

      // Create buyer groups
      final List<BuyerGroup> buyerGroupsList = [];
      for (final entry in buyerGroups.entries) {
        final parts = entry.key.split('|');
        final buyerId = parts[0];
        final buyerName = parts.length > 1 ? parts[1] : 'Unknown Buyer';

        // Sort transactions within buyer group by time (newest first)
        final sortedTransactions = entry.value
          ..sort((a, b) {
            final timestampA = (a.data() as Map<String, dynamic>)['timestamp']
                    is Timestamp
                ? (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp
                : null;
            final timestampB = (b.data() as Map<String, dynamic>)['timestamp']
                    is Timestamp
                ? (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp
                : null;

            if (timestampA == null && timestampB == null) return 0;
            if (timestampA == null) return 1;
            if (timestampB == null) return -1;

            return timestampB.compareTo(timestampA);
          });

        buyerGroupsList.add(BuyerGroup(
          buyerId: buyerId,
          buyerName: buyerName,
          transactions: sortedTransactions,
        ));
      }

      buyerGroupsList.sort((a, b) {
        final aLatestTimestamp = (a.transactions.first.data()
            as Map<String, dynamic>)['timestamp'] as Timestamp?;
        final bLatestTimestamp = (b.transactions.first.data()
            as Map<String, dynamic>)['timestamp'] as Timestamp?;

        if (aLatestTimestamp == null && bLatestTimestamp == null) return 0;
        if (aLatestTimestamp == null) return 1;
        if (bLatestTimestamp == null) return -1;

        return bLatestTimestamp.compareTo(aLatestTimestamp);
      });

      result.add(CategorizedShopTransactions(
        date: dateKey,
        buyerGroups: buyerGroupsList,
      ));
    }

    // ✅ OPTIMIZATION: Cache the result for future use
    _lastCategorizedInput = transactions;
    _memoizedCategorizedResult = result;

    return result;
  }

  Future<void> _onRefresh() async {
    try {
      await context.read<SellerPanelProvider>().fetchTransactions(
            shopId: context.read<SellerPanelProvider>().selectedShop?.id,
            forceRefresh: true,
          );
    } catch (e) {
      // optionally show a SnackBar or log the error
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    _throttle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      bottom: true,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFF2563EB),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header Section
              SliverToBoxAdapter(
                child: _HeaderSection(
                  searchController: _searchController,
                  isSearchMode: _isSearchMode,
                  isSearching: _isSearching,
                ),
              ),
              const SliverToBoxAdapter(child: _SummaryCards()),
              // Dynamic transaction list based on search mode
              _isSearchMode
                  ? _buildSearchResults()
                  : _buildRegularTransactions(),
              _buildBottomLoader(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_isSearching) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2563EB),
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/empty-search-result.png',
              width: 150,
              height: 150,
              color: isDarkMode ? Colors.white.withOpacity(0.3) : null,
              colorBlendMode:
                  isDarkMode ? BlendMode.srcATop : BlendMode.srcOver,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noTransactionsForSelectedDates,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ],
        ),
      );
    }

    // Categorize search results using the same logic as regular transactions
    final categorizedSearchResults = _categorizeTransactions(_searchResults);

    // Build flat display items for lazy loading
    final displayItems = _buildSearchDisplayItems(categorizedSearchResults);

    // Total items: header + display items + optional loading indicator
    final totalCount =
        1 + displayItems.length + (_isLoadingMoreSearchResults ? 1 : 0);

    // OPTIMIZATION: Use SliverChildBuilderDelegate for lazy widget creation
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // First item is always the search header
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (isDarkMode ? Colors.tealAccent : Colors.teal)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isDarkMode ? Colors.tealAccent : Colors.teal)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: isDarkMode ? Colors.tealAccent : Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.searchResults}: ${_searchResults.length}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ],
              ),
            );
          }

          // Last item is loading indicator (if loading)
          if (_isLoadingMoreSearchResults && index == totalCount - 1) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDarkMode ? Colors.tealAccent : Colors.teal,
                  ),
                ),
              ),
            );
          }

          // Display items (index - 1 because of header)
          final itemIndex = index - 1;
          if (itemIndex >= 0 && itemIndex < displayItems.length) {
            final item = displayItems[itemIndex];
            switch (item.type) {
              case _DisplayItemType.dateHeader:
                return _DateHeaderWidget(
                  date: item.date!,
                  isDarkMode: isDarkMode,
                );
              case _DisplayItemType.buyerHeader:
                return _BuyerHeaderWidget(
                  buyerName: item.buyerName!,
                  transactionCount: item.transactionCount!,
                );
              case _DisplayItemType.transaction:
                return Padding(
                  padding:
                      const EdgeInsets.only(left: 28, right: 16, bottom: 8),
                  child: _TransactionItem(
                    key: ValueKey(item.transactionDoc!.id),
                    transactionDoc: item.transactionDoc!,
                    l10n: l10n,
                    isDarkMode: isDarkMode,
                  ),
                );
            }
          }

          return const SizedBox.shrink();
        },
        childCount: totalCount,
        addAutomaticKeepAlives: true,
      ),
    );
  }

  /// Builds flat display items from categorized search results for lazy loading
  List<_DisplayItem> _buildSearchDisplayItems(
      List<CategorizedShopTransactions> categorizedResults) {
    final items = <_DisplayItem>[];
    for (final dateGroup in categorizedResults) {
      items.add(_DisplayItem.dateHeader(dateGroup.date));
      for (final buyerGroup in dateGroup.buyerGroups) {
        items.add(_DisplayItem.buyerHeader(
          buyerGroup.buyerName,
          buyerGroup.transactions.length,
        ));
        for (final transaction in buyerGroup.transactions) {
          items.add(_DisplayItem.transaction(transaction));
        }
      }
    }
    return items;
  }

  Widget _buildRegularTransactions() {
    return ValueListenableBuilder<List<DocumentSnapshot>>(
      valueListenable:
          context.read<SellerPanelProvider>().filteredTransactionsNotifier,
      builder: (context, transactions, _) {
        // Categorize transactions (memoized for performance)
        final categorized = _categorizeTransactions(transactions);

        return _CategorizedTransactionList(
          categorizedTransactions: categorized,
        );
      },
    );
  }

  Widget _buildBottomLoader() {
    if (_isSearchMode) {
      return SliverToBoxAdapter(
        child: _isLoadingMoreSearchResults
            ? const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2563EB),
                    strokeWidth: 3,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    } else {
      return const _BottomLoader();
    }
  }

  @override
  bool get wantKeepAlive => true;
}

// Updated header section to show search state
class _HeaderSection extends StatelessWidget {
  final TextEditingController searchController;
  final bool isSearchMode;
  final bool isSearching;

  const _HeaderSection({
    required this.searchController,
    required this.isSearchMode,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withOpacity(0.2)
            : Colors.white.withOpacity(0.8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black26
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _SearchBar(
            searchController: searchController,
            isSearching: isSearching,
          ),
          const SizedBox(height: 8),
          // Only show filter bar when NOT in search mode
          if (!isSearchMode) const _FilterBar(),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Selector<SellerPanelProvider, (bool, DateTime?, DateTimeRange?)>(
      selector: (_, p) => (
        p.isSingleDateMode,
        p.selectedDate,
        p.selectedDateRange,
      ),
      builder: (_, data, __) {
        final isSingleDateMode = data.$1;
        final selectedDate = data.$2;
        final selectedDateRange = data.$3;

        return Row(
          children: [
            // Date mode toggle buttons
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2A2D3A) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isDarkMode ? Colors.grey.shade600 : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeButton(
                    context,
                    l10n.singleDate,
                    isSingleDateMode,
                    () =>
                        Provider.of<SellerPanelProvider>(context, listen: false)
                            .setDateMode(true),
                    isFirst: true,
                  ),
                  _buildModeButton(
                    context,
                    l10n.dateRange,
                    !isSingleDateMode,
                    () =>
                        Provider.of<SellerPanelProvider>(context, listen: false)
                            .setDateMode(false),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Date picker button
            Expanded(
              child: GestureDetector(
                onTap: () => isSingleDateMode
                    ? _selectDate(context)
                    : _selectDateRange(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2A2D3A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.grey.shade600
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDarkMode
                            ? Colors.black26
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedDate != null
                              ? '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'
                              : selectedDateRange != null
                                  ? '${selectedDateRange.start.day}/${selectedDateRange.start.month} - ${selectedDateRange.end.day}/${selectedDateRange.end.month}'
                                  : l10n.selectDate,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selectedDate != null ||
                                    selectedDateRange != null
                                ? (isDarkMode ? Colors.white : Colors.black87)
                                : (isDarkMode
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (selectedDate != null || selectedDateRange != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.read<SellerPanelProvider>().clearFilters(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.shade300,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.clear_rounded,
                    size: 16,
                    color: Colors.red.shade600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildModeButton(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                )
              : null,
          color: !isSelected
              ? (isDark ? const Color(0xFF2A2D3A) : Colors.white)
              : null,
          borderRadius: BorderRadius.only(
            topLeft: isFirst ? const Radius.circular(7) : Radius.zero,
            bottomLeft: isFirst ? const Radius.circular(7) : Radius.zero,
            topRight: isLast ? const Radius.circular(7) : Radius.zero,
            bottomRight: isLast ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          context.read<SellerPanelProvider>().selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  surface: Color.fromARGB(255, 37, 35, 54),
                  onSurface: Colors.white,
                )
              : const ColorScheme.light(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
          textButtonTheme: isDark
              ? TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                )
              : null,
          dialogTheme: DialogThemeData(
              backgroundColor:
                  isDark ? const Color.fromARGB(255, 37, 35, 54) : null),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      context.read<SellerPanelProvider>().setFilterDate(picked);
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: context.read<SellerPanelProvider>().selectedDateRange,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  surface: Color.fromARGB(255, 37, 35, 54),
                  onSurface: Colors.white,
                )
              : const ColorScheme.light(
                  primary: Colors.orange,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
          textButtonTheme: isDark
              ? TextButtonThemeData(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                )
              : null,
          dialogTheme: DialogThemeData(
              backgroundColor:
                  isDark ? const Color.fromARGB(255, 37, 35, 54) : null),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      context.read<SellerPanelProvider>().setFilterRange(picked);
    }
  }
}

// Updated search bar with search indicator
class _SearchBar extends StatelessWidget {
  final TextEditingController searchController;
  final bool isSearching;

  const _SearchBar({
    required this.searchController,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: searchController,
        style: TextStyle(
          fontSize: 14,
          fontFamily: 'Figtree',
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            child: isSearching
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.tealAccent : Colors.teal,
                      ),
                    ),
                  )
                : Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
          ),
          suffixIcon: searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    searchController.clear();
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.clear_rounded,
                      size: 16,
                      color:
                          isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                  ),
                ),
          hintText: l10n.searchProducts,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          filled: true,
          fillColor: isDark ? const Color(0xFF2A2D3A) : Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isDark ? Colors.tealAccent : Colors.teal,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Selector<SellerPanelProvider, (double, double)>(
      selector: (_, p) => (p.todaySales, p.totalSales),
      builder: (_, data, __) {
        final todaySales = data.$1;
        final totalSales = data.$2;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // Today's Sales Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.today_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.today,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${todaySales.toStringAsFixed(2)} TL",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Total Sales Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.trending_up_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Total', // You might want to add this to your localization
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${totalSales.toStringAsFixed(2)} TL",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Display item types for lazy list building
enum _DisplayItemType { dateHeader, buyerHeader, transaction }

/// Lightweight descriptor for lazy building - avoids creating widgets upfront
class _DisplayItem {
  final _DisplayItemType type;
  final String? date;
  final String? buyerName;
  final int? transactionCount;
  final DocumentSnapshot? transactionDoc;

  const _DisplayItem.dateHeader(this.date)
      : type = _DisplayItemType.dateHeader,
        buyerName = null,
        transactionCount = null,
        transactionDoc = null;

  const _DisplayItem.buyerHeader(this.buyerName, this.transactionCount)
      : type = _DisplayItemType.buyerHeader,
        date = null,
        transactionDoc = null;

  const _DisplayItem.transaction(this.transactionDoc)
      : type = _DisplayItemType.transaction,
        date = null,
        buyerName = null,
        transactionCount = null;
}

// Modified transaction list with lazy loading via SliverChildBuilderDelegate
class _CategorizedTransactionList extends StatelessWidget {
  final List<CategorizedShopTransactions> categorizedTransactions;

  const _CategorizedTransactionList({
    required this.categorizedTransactions,
  });

  /// Flattens categorized transactions into indexable display items
  List<_DisplayItem> _buildDisplayItems() {
    final items = <_DisplayItem>[];
    for (final dateGroup in categorizedTransactions) {
      items.add(_DisplayItem.dateHeader(dateGroup.date));
      for (final buyerGroup in dateGroup.buyerGroups) {
        items.add(_DisplayItem.buyerHeader(
          buyerGroup.buyerName,
          buyerGroup.transactions.length,
        ));
        for (final transaction in buyerGroup.transactions) {
          items.add(_DisplayItem.transaction(transaction));
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Check if shop is selected
    return Selector<SellerPanelProvider, (bool, String?)>(
      selector: (_, p) => (p.selectedShop == null, p.selectedShop?.id),
      builder: (_, data, __) {
        final noShopSelected = data.$1;

        if (noShopSelected) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1F2937) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.black.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.1),
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.store_rounded,
                      size: 48,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.noShopSelected,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color:
                          isDarkMode ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please select a shop to view transactions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: isDarkMode
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (categorizedTransactions.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/empty-search-result.png',
                  width: 150,
                  height: 150,
                  color: isDarkMode ? Colors.white.withOpacity(0.3) : null,
                  colorBlendMode:
                      isDarkMode ? BlendMode.srcATop : BlendMode.srcOver,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.noTransactionsForSelectedDates,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          );
        }

        // Build flat list of display items for lazy loading
        final displayItems = _buildDisplayItems();

        return SliverList(
          // OPTIMIZATION: Use SliverChildBuilderDelegate for lazy widget creation
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = displayItems[index];

              switch (item.type) {
                case _DisplayItemType.dateHeader:
                  return _DateHeaderWidget(
                    date: item.date!,
                    isDarkMode: isDarkMode,
                  );
                case _DisplayItemType.buyerHeader:
                  return _BuyerHeaderWidget(
                    buyerName: item.buyerName!,
                    transactionCount: item.transactionCount!,
                  );
                case _DisplayItemType.transaction:
                  return Padding(
                    padding:
                        const EdgeInsets.only(left: 28, right: 16, bottom: 8),
                    child: _TransactionItem(
                      key: ValueKey(item.transactionDoc!.id),
                      transactionDoc: item.transactionDoc!,
                      l10n: l10n,
                      isDarkMode: isDarkMode,
                    ),
                  );
              }
            },
            childCount: displayItems.length,
            // Enable addAutomaticKeepAlives for smoother scrolling
            addAutomaticKeepAlives: true,
          ),
        );
      },
    );
  }
}

/// Extracted date header widget for cleaner code
class _DateHeaderWidget extends StatelessWidget {
  final String date;
  final bool isDarkMode;

  const _DateHeaderWidget({
    required this.date,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color.fromARGB(255, 45, 42, 65)
            : const Color.fromARGB(255, 248, 249, 250),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode
              ? const Color.fromARGB(255, 60, 57, 78)
              : const Color.fromARGB(255, 230, 232, 236),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: isDarkMode ? Colors.white70 : Colors.grey[700],
          ),
          const SizedBox(width: 12),
          Text(
            date,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white70 : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

/// Extracted buyer header widget for cleaner code
class _BuyerHeaderWidget extends StatelessWidget {
  final String buyerName;
  final int transactionCount;

  const _BuyerHeaderWidget({
    required this.buyerName,
    required this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 8, 16, 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.person_rounded,
              size: 16,
              color: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              buyerName,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$transactionCount',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Individual transaction item widget to minimize rebuilds
class _TransactionItem extends StatelessWidget {
  final DocumentSnapshot transactionDoc;
  final AppLocalizations l10n;
  final bool isDarkMode;

  const _TransactionItem({
    super.key,
    required this.transactionDoc,
    required this.l10n,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final data = transactionDoc.data() as Map<String, dynamic>;
    final transactionId = transactionDoc.id;

    // Pull everything straight out of the transaction
    final productId = data['productId'] as String? ?? '';
    final imageUrl = data['selectedColorImage'] as String? ??
        data['productImage'] as String? ??
        '';
    final name = data['productName'] as String? ?? '';
    final avgRating = (data['averageRating'] as num?)?.toDouble() ?? 0.0;
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final currency = data['currency'] as String? ?? 'TRY';
    final quantity = (data['quantity'] as num?)?.toInt() ?? 1;

    // Get selected attributes from the document
    final selectedAttributes =
        data['selectedAttributes'] as Map<String, dynamic>? ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final orderId = data['orderId'] as String?;
            final shopId = context.read<SellerPanelProvider>().selectedShop?.id;

            if (orderId != null && shopId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SellerPanelOrderDetailsScreen(
                    orderId: orderId,
                    shopId: shopId,
                  ),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProductCard4(
                        key: ValueKey(transactionId),
                        imageUrl: imageUrl,
                        colorImages: const <String, List<String>>{},
                        selectedColor:
                            selectedAttributes['selectedColor'] as String?,
                        productName: name,
                        brandModel: '',
                        price: price,
                        currency: currency,
                        averageRating: avgRating,
                        productId: productId,
                      ),

                      // UPDATED: Use the same dynamic attributes UI as SellerPanelOrderDetailsScreen
                      const SizedBox(height: 12),
                      _buildDynamicAttributesSection(
                          selectedAttributes, quantity),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Icon(
                    Icons.chevron_right,
                    color: const Color(0xFF00A86B),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds localized attribute displays from selectedAttributes and quantity
  Widget _buildDynamicAttributesSection(
      Map<String, dynamic> selectedAttributes, int quantity) {
    final List<Widget> attributeChips = [];

    // Define color palette for different attribute types
    final List<Color> colorPalette = [
      const Color(0xFF6366F1), // primary
      const Color(0xFF8B5CF6), // purple
      const Color(0xFF10B981), // green
      const Color(0xFFF59E0B), // amber
      const Color(0xFF3B82F6), // blue
      const Color(0xFF06B6D4), // cyan
      const Color(0xFFEF4444), // red
    ];

    int colorIndex = 0;

    // Add quantity first with first color
    final quantityColor = colorPalette[colorIndex % colorPalette.length];
    colorIndex++;

    attributeChips.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: quantityColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${l10n.quantity}: ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: quantityColor,
                ),
              ),
              TextSpan(
                text: quantity.toString(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: quantityColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // System fields list (same as before)
    final systemFields = {
      // Document identifiers
      'productId', 'orderId', 'buyerId', 'sellerId',
      // Timestamps
      'timestamp', 'addedAt', 'updatedAt',
      // Images (not user selections)
      'selectedColorImage', 'productImage',
      // Pricing fields (calculated by cart/system)
      'price', 'finalPrice', 'calculatedUnitPrice', 'calculatedTotal',
      'unitPrice', 'totalPrice', 'currency',
      // Bundle/sale system fields
      'isBundleItem', 'bundleInfo', 'salePreferences', 'isBundle',
      'bundleId', 'mainProductPrice', 'bundlePrice',
      // Seller info (displayed elsewhere)
      'sellerName', 'isShop', 'shopId',
      // Product metadata (not user choices)
      'productName', 'brandModel', 'brand', 'category', 'subcategory',
      'subsubcategory', 'condition', 'averageRating', 'productAverageRating',
      'reviewCount', 'productReviewCount', 'gender', 'clothingType',
      'clothingFit',
      // Order/shipping status
      'shipmentStatus', 'deliveryOption', 'needsProductReview',
      'needsSellerReview', 'needsAnyReview',
      // System quantities
      'quantity', 'availableStock', 'maxQuantityAllowed', 'ourComission',
      'sellerContactNo', 'showSellerHeader',
      'clothingTypes',
      'pantFabricTypes',
      'pantFabricType',
    };

    // Process user-selected attributes (same as before)
    selectedAttributes.forEach((key, value) {
      if (value == null ||
          value.toString().isEmpty ||
          (value is List && value.isEmpty) ||
          systemFields.contains(key)) {
        return;
      }

      try {
        final localizedKey =
            AttributeLocalizationUtils.getLocalizedAttributeTitle(key, l10n);
        final localizedValue =
            AttributeLocalizationUtils.getLocalizedAttributeValue(
                key, value, l10n);

        final currentColor = colorPalette[colorIndex % colorPalette.length];
        colorIndex++;

        attributeChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: currentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$localizedKey: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: currentColor,
                    ),
                  ),
                  TextSpan(
                    text: localizedValue,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: currentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        if (!systemFields.contains(key)) {
          final fallbackColor = colorPalette[colorIndex % colorPalette.length];
          colorIndex++;

          attributeChips.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: fallbackColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$key: $value',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fallbackColor,
                ),
              ),
            ),
          );
        }
      }
    });

    // Return wrapped chips with discount labels
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attributeChips.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: attributeChips,
          ),

        // ADD: Discount labels section
        const SizedBox(height: 8),
        _buildDiscountLabels(),
      ],
    );
  }

// NEW: Add this method to _TransactionItem class
  Widget _buildDiscountLabels() {
    final data = transactionDoc.data() as Map<String, dynamic>;
    final discountLabels = <Widget>[];

    // Check for bundle discount - USE ORIGINAL PERCENTAGE
    final bundleInfo = data['bundleInfo'] as Map<String, dynamic>?;
    if (bundleInfo != null && bundleInfo['wasInBundle'] == true) {
      // Use originalBundleDiscountPercentage if available, fallback to calculated bundleDiscount
      final bundleDiscount =
          bundleInfo['originalBundleDiscountPercentage'] as int? ??
              bundleInfo['bundleDiscount'] as int? ??
              0;

      if (bundleDiscount > 0) {
        discountLabels.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade600],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.card_giftcard_rounded,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _getBundleDiscountText(bundleDiscount),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Check for sale preference discount
    final salePreferenceInfo =
        data['salePreferenceInfo'] as Map<String, dynamic>?;
    if (salePreferenceInfo != null &&
        salePreferenceInfo['discountApplied'] == true) {
      final discountPercentage =
          salePreferenceInfo['discountPercentage'] as int? ?? 0;
      if (discountPercentage > 0) {
        discountLabels.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade400, Colors.orange.shade600],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _getSaleDiscountText(discountPercentage),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (discountLabels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: discountLabels,
    );
  }

// NEW: Add these helper methods to _TransactionItem class
  String _getBundleDiscountText(int discountPercentage) {
    switch (l10n.localeName) {
      case 'tr':
        return 'Paket İndirimi $discountPercentage%';
      case 'ru':
        return 'Скидка на пакет $discountPercentage%';
      default:
        return 'Bundle Discount $discountPercentage%';
    }
  }

  String _getSaleDiscountText(int discountPercentage) {
    switch (l10n.localeName) {
      case 'tr':
        return 'Toplu Alım indirimi $discountPercentage%';
      case 'ru':
        return 'Скидка на покупку в количестве $discountPercentage%';
      default:
        return 'Bulk Purchase discount $discountPercentage%';
    }
  }
}

class _BottomLoader extends StatelessWidget {
  const _BottomLoader();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          context.read<SellerPanelProvider>().isLoadingMoreTransactionsNotifier,
      builder: (context, isFetching, _) {
        if (isFetching) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                  strokeWidth: 3,
                ),
              ),
            ),
          );
        }

        return const SliverToBoxAdapter(child: SizedBox.shrink());
      },
    );
  }
}
