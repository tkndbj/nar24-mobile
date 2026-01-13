import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../screens/PAYMENT-RECEIPT/sold_product_screen.dart';
import '../../screens/PAYMENT-RECEIPT/shipment_status_screen.dart';
import '../../../providers/my_products_provider.dart';
import '../../services/algolia_service_manager.dart';

/// Shipment status enum matching Firestore structure (from shipments_tab.dart)
enum BuyerShipmentStatus {
  pending, // gatheringStatus: 'pending' - waiting for cargo assignment
  collecting, // gatheringStatus: 'assigned' - cargo person assigned, going to collect
  inTransit, // gatheringStatus: 'gathered' - collected, on way to warehouse
  atWarehouse, // gatheringStatus: 'at_warehouse' - at warehouse, ready for distribution
  outForDelivery, // distributionStatus: 'assigned' - out for delivery
  delivered, // deliveredInPartial: true - delivered to customer
  failed, // gatheringStatus: 'failed' - delivery failed
}

// Helper class for categorized transactions
class CategorizedTransactions {
  final String date;
  final List<SellerGroup> sellerGroups;

  CategorizedTransactions({
    required this.date,
    required this.sellerGroups,
  });
}

class SellerGroup {
  final String sellerId;
  final String sellerName;
  final List<Map<String, dynamic>> transactions;

  SellerGroup({
    required this.sellerId,
    required this.sellerName,
    required this.transactions,
  });
}

class SoldBoughtProductsTab extends StatefulWidget {
  final bool isSold;

  const SoldBoughtProductsTab({
    Key? key,
    required this.isSold,
  }) : super(key: key);

  @override
  State<SoldBoughtProductsTab> createState() => SoldBoughtProductsTabState();
}

class SoldBoughtProductsTabState extends State<SoldBoughtProductsTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // Configuration
  static const int _pageSize = 20;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 300);
  static const Duration _scrollThrottleDelay = Duration(milliseconds: 100);
  static const double _loadMoreTriggerOffset = 0.8;

  @override
  bool get wantKeepAlive => true;

  // Controllers and state
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _scrollController = ScrollController();
  late TabController _tabController;

  // Data management
  final List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  final Set<String> _loadedTransactionIds = {};

  // Categorized data for bought products
  List<CategorizedTransactions> _categorizedTransactions = [];

  DocumentSnapshot? _lastDoc;
  bool _loadingMore = false;
  bool _isLoadingInitial = true;
  bool _hasReachedEnd = false;

  // Search state
  String _currentSearchQuery = '';
  bool _isSearchMode = false;
  bool _isSearching = false;
  bool _isLoadingMoreSearchResults = false;
  List<DocumentSnapshot> _searchResults = [];
  List<Map<String, dynamic>> _currentAlgoliaResults = [];
  int _currentSearchPage = 0;
  bool _hasMoreSearchResults = true;
  String _lastSearchQuery = '';

  // Debouncing and throttling
  Timer? _scrollThrottle;
  Timer? _searchDebounce;

  // Error handling
  String? _errorMessage;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupListeners();
    _loadInitialPage();
  }

  void _initializeControllers() {
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isSold ? 0 : 1,
    );
  }

  void applySearch(String query) {
    if (!mounted) return;

    final trimmedQuery = query.trim();

    // Immediate UI feedback
    if (trimmedQuery.isNotEmpty && !_isSearchMode) {
      setState(() {
        _isSearchMode = true;
      });
    } else if (trimmedQuery.isEmpty && _isSearchMode) {
      setState(() {
        _isSearchMode = false;
        _searchResults = [];
        _currentAlgoliaResults = [];
        _isSearching = false;
        _isLoadingMoreSearchResults = false;
        _lastSearchQuery = '';
        _currentSearchPage = 0;
        _hasMoreSearchResults = true;
      });
      return;
    }

    // Debounced search execution
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (mounted) {
        if (trimmedQuery.isNotEmpty) {
          _performAlgoliaSearch(trimmedQuery);
        } else {
          _currentSearchQuery = '';
          setState(() {
            _isSearchMode = false;
            _searchResults = [];
            _currentAlgoliaResults = [];
            _isSearching = false;
            _isLoadingMoreSearchResults = false;
            _lastSearchQuery = '';
            _currentSearchPage = 0;
            _hasMoreSearchResults = true;
          });
        }
      }
    });

    setState(() {
      _currentSearchQuery = trimmedQuery;
    });
  }

  Future<void> _performAlgoliaSearch(String query) async {
    final userId = _auth.currentUser?.uid;

    if (userId == null) {
      debugPrint('❌ No authenticated user for Algolia search');
      return;
    }

    if (query == _lastSearchQuery && _isSearchMode) return;

    debugPrint('🔍 === ALGOLIA ORDERS SEARCH DEBUG ===');
    debugPrint('🔍 Query: "$query"');
    debugPrint('🔍 User ID: "$userId"');
    debugPrint('🔍 Is Sold: ${widget.isSold}');

    setState(() {
      _isSearching = true;
      _lastSearchQuery = query;
      _currentSearchPage = 0;
      _hasMoreSearchResults = true;
    });

    try {
      final results = await AlgoliaServiceManager.instance.ordersService
          .searchOrdersInAlgolia(
        query: query,
        userId: userId,
        isSold: widget.isSold,
        page: 0,
        hitsPerPage: 20,
      );

      debugPrint('🔍 Algolia Results Count: ${results.length}');

      if (results.isNotEmpty) {
        debugPrint('🔍 First 3 Results:');
        for (int i = 0; i < results.take(3).length; i++) {
          final hit = results[i];
          final productName = hit['productName'] ?? 'Unknown';
          final sellerName = hit['sellerName'] ?? 'Unknown Seller';
          final buyerName = hit['buyerName'] ?? 'Unknown Buyer';
          debugPrint(
              '  ${i + 1}. $productName (Seller: $sellerName, Buyer: $buyerName)');
        }
      }

      final documentSnapshots = await AlgoliaServiceManager
          .instance.ordersService
          .fetchDocumentSnapshotsFromAlgoliaResults(results);

      setState(() {
        _currentAlgoliaResults = results;
        _searchResults = documentSnapshots;
        _hasMoreSearchResults = results.length == 20;
        _isSearching = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Algolia orders search error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      setState(() {
        _searchResults = [];
        _hasMoreSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _loadMoreSearchResults() async {
    final userId = _auth.currentUser?.uid;

    if (userId == null ||
        !_hasMoreSearchResults ||
        _isLoadingMoreSearchResults ||
        !_isSearchMode) {
      return;
    }

    setState(() {
      _isLoadingMoreSearchResults = true;
      _currentSearchPage++;
    });

    try {
      final results = await AlgoliaServiceManager.instance.ordersService
          .searchOrdersInAlgolia(
        query: _lastSearchQuery,
        userId: userId,
        isSold: widget.isSold,
        page: _currentSearchPage,
        hitsPerPage: 20,
      );

      final newDocumentSnapshots = await AlgoliaServiceManager
          .instance.ordersService
          .fetchDocumentSnapshotsFromAlgoliaResults(results);

      setState(() {
        _currentAlgoliaResults.addAll(results);
        _searchResults.addAll(newDocumentSnapshots);
        _hasMoreSearchResults = results.length == 20;
        _isLoadingMoreSearchResults = false;
      });
    } catch (e) {
      debugPrint('Load more search results error: $e');
      setState(() {
        _hasMoreSearchResults = false;
        _isLoadingMoreSearchResults = false;
      });
    }
  }

  void _setupListeners() {
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollThrottle?.isActive ?? false) return;

    _scrollThrottle = Timer(_scrollThrottleDelay, () {
      if (!mounted) return;

      final position = _scrollController.position;
      if (position.pixels >=
          position.maxScrollExtent * _loadMoreTriggerOffset) {
        if (_isSearchMode) {
          if (!_isLoadingMoreSearchResults && _hasMoreSearchResults) {
            _loadMoreSearchResults();
          }
        } else {
          if (!_loadingMore && !_hasReachedEnd && _errorMessage == null) {
            _loadNextPage();
          }
        }
      }
    });
  }

  Future<void> _loadInitialPage() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoadingInitial = true;
        _errorMessage = null;
        _retryCount = 0;
      });

      await _resetPagination();

      final isSold = widget.isSold;
      await _loadTransactionsPage(isSold, isInitial: true);
    } catch (e) {
      _handleLoadError(e, isInitial: true);
    }
  }

  Future<void> _resetPagination() async {
    _allTransactions.clear();
    _filteredTransactions.clear();
    _categorizedTransactions.clear();
    _loadedTransactionIds.clear();
    _lastDoc = null;
    _hasReachedEnd = false;

    final provider = Provider.of<MyProductsProvider>(context, listen: false);
    provider.clearTransactionCache();
  }

  Future<void> _loadNextPage() async {
    if (!mounted || _loadingMore || _hasReachedEnd || _lastDoc == null) return;

    try {
      setState(() {
        _loadingMore = true;
        _errorMessage = null;
      });

      final isSold = widget.isSold;
      await _loadTransactionsPage(isSold, isInitial: false);
    } catch (e) {
      _handleLoadError(e, isInitial: false);
    }
  }

  Future<void> _loadTransactionsPage(bool isSold,
      {required bool isInitial}) async {
    final provider = Provider.of<MyProductsProvider>(context, listen: false);
    final userId = _auth.currentUser?.uid;

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final result = await provider.loadTransactions(
      firestore: _firestore,
      userId: userId,
      isSold: isSold,
      pageSize: _pageSize,
      lastTransactionDoc: isInitial ? null : _lastDoc,
    );

    if (!mounted) return;

    final newTransactions =
        result['transactions'] as List<Map<String, dynamic>>;
    final lastDoc = result['lastDoc'] as DocumentSnapshot?;

    // Filter out duplicates
    final uniqueTransactions = newTransactions.where((tx) {
      final id = tx['id'] as String;
      return !_loadedTransactionIds.contains(id);
    }).toList();

    // Add new transaction IDs to our set
    for (final tx in uniqueTransactions) {
      _loadedTransactionIds.add(tx['id'] as String);
    }

    setState(() {
      if (isInitial) {
        _allTransactions.clear();
        _allTransactions.addAll(uniqueTransactions);
        _filteredTransactions = List.from(_allTransactions);
        _isLoadingInitial = false;
      } else {
        _allTransactions.addAll(uniqueTransactions);
        _filteredTransactions = List.from(_allTransactions);
        _loadingMore = false;
      }

      _lastDoc = lastDoc;
      _hasReachedEnd = uniqueTransactions.length < _pageSize || lastDoc == null;
      _retryCount = 0;

      // Update categorized transactions for bought products
      if (!widget.isSold) {
        _categorizedTransactions =
            _categorizeTransactions(_filteredTransactions);
      }
    });
  }

  List<CategorizedTransactions> _categorizeTransactions(
      List<Map<String, dynamic>> transactions) {
    // Group by date first
    final Map<String, List<Map<String, dynamic>>> dateGroups = {};
    final DateFormat dateFormatter = DateFormat('dd/MM/yyyy');

    for (final tx in transactions) {
      final data = tx['data'] as Map<String, dynamic>;
      final timestamp = data['timestamp'] is Timestamp
          ? data['timestamp'] as Timestamp
          : null;

      if (timestamp != null) {
        final date = timestamp.toDate();
        final dateKey = dateFormatter.format(date);

        if (!dateGroups.containsKey(dateKey)) {
          dateGroups[dateKey] = [];
        }
        dateGroups[dateKey]!.add(tx);
      }
    }

    // Sort dates in descending order (newest first)
    final sortedDates = dateGroups.keys.toList()
      ..sort((a, b) {
        final dateA = DateFormat('dd/MM/yyyy').parse(a);
        final dateB = DateFormat('dd/MM/yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    final List<CategorizedTransactions> result = [];

    for (final dateKey in sortedDates) {
      final dateTransactions = dateGroups[dateKey]!;

      // Group by seller within each date
      final Map<String, List<Map<String, dynamic>>> sellerGroups = {};

      for (final tx in dateTransactions) {
        final data = tx['data'] as Map<String, dynamic>;
        final sellerId = data['sellerId'] as String? ?? 'unknown';
        final sellerName = data['sellerName'] as String? ?? 'Unknown Seller';

        final sellerKey =
            '$sellerId|$sellerName'; // Use both ID and name for uniqueness

        if (!sellerGroups.containsKey(sellerKey)) {
          sellerGroups[sellerKey] = [];
        }
        sellerGroups[sellerKey]!.add(tx);
      }

      // Create seller groups
      final List<SellerGroup> sellerGroupsList = [];
      for (final entry in sellerGroups.entries) {
        final parts = entry.key.split('|');
        final sellerId = parts[0];
        final sellerName = parts.length > 1 ? parts[1] : 'Unknown Seller';

        // Sort transactions within seller group by time (newest first)
        final sortedTransactions = entry.value
          ..sort((a, b) {
            final timestampA = (a['data'] as Map<String, dynamic>)['timestamp']
                    is Timestamp
                ? (a['data'] as Map<String, dynamic>)['timestamp'] as Timestamp
                : null;
            final timestampB = (b['data'] as Map<String, dynamic>)['timestamp']
                    is Timestamp
                ? (b['data'] as Map<String, dynamic>)['timestamp'] as Timestamp
                : null;

            if (timestampA == null && timestampB == null) return 0;
            if (timestampA == null) return 1;
            if (timestampB == null) return -1;

            return timestampB.compareTo(timestampA);
          });

        sellerGroupsList.add(SellerGroup(
          sellerId: sellerId,
          sellerName: sellerName,
          transactions: sortedTransactions,
        ));
      }

      // Sort seller groups by seller name
      sellerGroupsList.sort((a, b) => a.sellerName.compareTo(b.sellerName));

      result.add(CategorizedTransactions(
        date: dateKey,
        sellerGroups: sellerGroupsList,
      ));
    }

    return result;
  }

  void _handleLoadError(dynamic error, {required bool isInitial}) {
    if (!mounted) return;

    debugPrint('Error loading transactions: $error');

    setState(() {
      if (isInitial) {
        _isLoadingInitial = false;
      } else {
        _loadingMore = false;
      }

      _errorMessage = _getErrorMessage(error);
    });
  }

  String _getErrorMessage(dynamic error) {
    if (error.toString().contains('network')) {
      return 'Network error. Please check your connection.';
    } else if (error.toString().contains('permission')) {
      return 'Permission denied. Please try logging in again.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<void> _retryLoad() async {
    if (_retryCount >= _maxRetries) return;

    _retryCount++;

    if (_isLoadingInitial) {
      await _loadInitialPage();
    } else {
      await _loadNextPage();
    }
  }

  Future<void> _refreshData() async {
    _currentSearchQuery = '';
    _isSearchMode = false;
    _searchResults = [];
    _currentAlgoliaResults = [];
    _isSearching = false;
    _isLoadingMoreSearchResults = false;
    _lastSearchQuery = '';
    _currentSearchPage = 0;
    _hasMoreSearchResults = true;

    await _loadInitialPage();
  }

  /// Determines the shipment status from item data (for bought products)
  BuyerShipmentStatus _getShipmentStatus(Map<String, dynamic> data) {
    final gatheringStatus = data['gatheringStatus'] as String?;

    // Check for failures first
    if (gatheringStatus == 'failed') {
      return BuyerShipmentStatus.failed;
    }

    // Check if item was delivered
    // Option 1: gatheringStatus is 'delivered' (from QR scan)
    // Option 2: deliveredInPartial is true (from partial delivery)
    // Option 3: deliveryStatus is 'delivered'
    final deliveredInPartial = data['deliveredInPartial'] as bool? ?? false;
    final deliveryStatus = data['deliveryStatus'] as String?;

    if (gatheringStatus == 'delivered' ||
        deliveredInPartial ||
        deliveryStatus == 'delivered') {
      return BuyerShipmentStatus.delivered;
    }

    // Check gathering status
    switch (gatheringStatus) {
      case 'at_warehouse':
        return BuyerShipmentStatus.atWarehouse;
      case 'gathered':
        return BuyerShipmentStatus.inTransit;
      case 'assigned':
        return BuyerShipmentStatus.collecting;
      case 'pending':
      default:
        return BuyerShipmentStatus.pending;
    }
  }

  /// Get localized status text
  String _getLocalizedStatus(
      BuyerShipmentStatus status, AppLocalizations l10n) {
    switch (status) {
      case BuyerShipmentStatus.pending:
        return l10n.shipmentPending;
      case BuyerShipmentStatus.collecting:
        return l10n.shipmentCollecting;
      case BuyerShipmentStatus.inTransit:
        return l10n.shipmentInTransit;
      case BuyerShipmentStatus.atWarehouse:
        return l10n.shipmentAtWarehouse;
      case BuyerShipmentStatus.outForDelivery:
        return l10n.shipmentOutForDelivery;
      case BuyerShipmentStatus.delivered:
        return l10n.shipmentDelivered;
      case BuyerShipmentStatus.failed:
        return l10n.shipmentFailed;
    }
  }

  /// Get status color
  Color _getStatusColor(BuyerShipmentStatus status) {
    switch (status) {
      case BuyerShipmentStatus.pending:
        return Colors.grey;
      case BuyerShipmentStatus.collecting:
        return Colors.orange;
      case BuyerShipmentStatus.inTransit:
        return Colors.blue;
      case BuyerShipmentStatus.atWarehouse:
        return Colors.purple;
      case BuyerShipmentStatus.outForDelivery:
        return Colors.indigo;
      case BuyerShipmentStatus.delivered:
        return const Color(0xFF00A86B);
      case BuyerShipmentStatus.failed:
        return Colors.red;
    }
  }

  /// Get status icon
  IconData _getStatusIcon(BuyerShipmentStatus status) {
    switch (status) {
      case BuyerShipmentStatus.pending:
        return Icons.schedule;
      case BuyerShipmentStatus.collecting:
        return Icons.person_pin_circle;
      case BuyerShipmentStatus.inTransit:
        return Icons.local_shipping;
      case BuyerShipmentStatus.atWarehouse:
        return Icons.warehouse;
      case BuyerShipmentStatus.outForDelivery:
        return Icons.delivery_dining;
      case BuyerShipmentStatus.delivered:
        return Icons.check_circle;
      case BuyerShipmentStatus.failed:
        return Icons.error;
    }
  }

  @override
  void dispose() {
    _scrollThrottle?.cancel();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildShimmerList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          height: 120,
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: isDark ? Colors.red.shade300 : Colors.red.shade600,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryLoad,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String message;
    if (_currentSearchQuery.isNotEmpty) {
      message = l10n.noOrdersFoundForSearch;
    } else {
      message = widget.isSold ? l10n.noSoldProducts : l10n.noBoughtProducts;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/empty-product.png',
            width: 150,
            height: 150,
            color: isDark ? Colors.white.withOpacity(0.3) : null,
            colorBlendMode: isDark ? BlendMode.srcATop : null,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          if (_currentSearchQuery.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.trySearchingWithDifferentKeywords,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty-product.png',
              width: 150,
              height: 150,
              color: isDark ? Colors.white.withOpacity(0.3) : null,
              colorBlendMode: isDark ? BlendMode.srcATop : null,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.youNeedToLoginToTrackYourProducts,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.push('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                elevation: 2,
              ),
              child: Text(
                l10n.loginButton,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            color: Color(0xFF00A86B),
            strokeWidth: 3,
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return _buildEmptyState(l10n);
    }

    // Convert search results to categorized format
    final searchTransactions = _searchResults
        .map((doc) => {
              'id': doc.id,
              'data': doc.data() as Map<String, dynamic>,
            })
        .toList();

    final categorizedSearchResults = widget.isSold
        ? searchTransactions // For sold products, keep flat for now or implement buyer categorization
        : _categorizeTransactions(searchTransactions);

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF00A86B),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Search results header
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (isDark ? Colors.tealAccent : Colors.teal).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isDark ? Colors.tealAccent : Colors.teal)
                      .withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: isDark ? Colors.tealAccent : Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.searchResults}: ${_searchResults.length}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Display categorized search results for bought products
          if (!widget.isSold && categorizedSearchResults.isNotEmpty) ...[
            ..._buildCategorizedSearchResultsSlivers(
                categorizedSearchResults as List<CategorizedTransactions>),
          ] else ...[
            // Display flat search results for sold products
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _searchResults.length) {
                      if (_isLoadingMoreSearchResults) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark ? Colors.tealAccent : Colors.teal,
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final transactionDoc = _searchResults[index];
                    final data = transactionDoc.data() as Map<String, dynamic>;
                    return _buildTransactionItem({
                      'id': transactionDoc.id,
                      'data': data,
                    });
                  },
                  childCount: _searchResults.length +
                      (_isLoadingMoreSearchResults ? 1 : 0),
                ),
              ),
            ),
          ],

          // Loading indicator
          if (_isLoadingMoreSearchResults)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildCategorizedSearchResultsSlivers(
      List<CategorizedTransactions> categorizedResults) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return categorizedResults
        .expand((dateGroup) => [
              // Date header
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color.fromARGB(255, 45, 42, 65)
                        : const Color.fromARGB(255, 248, 249, 250),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color.fromARGB(255, 60, 57, 78)
                          : const Color.fromARGB(255, 230, 232, 236),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 18,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                      const SizedBox(width: 12),
                      Text(
                        dateGroup.date,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Seller groups for this date
              ...dateGroup.sellerGroups.expand((sellerGroup) => [
                    // Seller header
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(24, 8, 12, 4),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A86B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.store_rounded,
                                size: 16,
                                color: const Color(0xFF00A86B),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sellerGroup.sellerName,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF00A86B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A86B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${sellerGroup.transactions.length} item${sellerGroup.transactions.length > 1 ? 's' : ''}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF00A86B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Products for this seller
                    SliverPadding(
                      padding:
                          const EdgeInsets.only(left: 24, right: 12, bottom: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _buildTransactionItem(
                              sellerGroup.transactions[index]),
                          childCount: sellerGroup.transactions.length,
                        ),
                      ),
                    ),
                  ]),
            ])
        .toList();
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final data = tx['data'] as Map<String, dynamic>;
    final tid = tx['id'] as String;

    final name = data['productName'] as String? ?? 'Unnamed';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final currency = data['currency'] as String? ?? 'TRY';
    final selImg = data['selectedColorImage'] as String?;
    final defaultImg = data['productImage'] as String? ?? '';
    final imageUrl = (selImg?.isNotEmpty == true) ? selImg! : defaultImg;
    final quantity = (data['quantity'] as num?)?.toInt() ?? 1;

    // Format time
    String timeText = '';
    final timestamp =
        data['timestamp'] is Timestamp ? data['timestamp'] as Timestamp : null;
    if (timestamp != null) {
      final time = timestamp.toDate();
      timeText = DateFormat('HH:mm').format(time);
    }

    // Get shipment status for bought products
    BuyerShipmentStatus? shipmentStatus;
    Color? statusColor;
    String? statusText;
    IconData? statusIcon;
    if (!widget.isSold) {
      shipmentStatus = _getShipmentStatus(data);
      statusColor = _getStatusColor(shipmentStatus);
      statusText = _getLocalizedStatus(shipmentStatus, l10n);
      statusIcon = _getStatusIcon(shipmentStatus);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.grey[200]!,
              blurRadius: 6,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _handleTransactionTap(data, tid),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column: Product image + shipment status
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Product card (will show image on left)
                            SizedBox(
                              width: 90,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        width: 90,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 90,
                                          height: 80,
                                          color: isDark
                                              ? Colors.grey[800]
                                              : Colors.grey[200],
                                          child: const Icon(Icons.image,
                                              color: Colors.grey),
                                        ),
                                      )
                                    : Container(
                                        width: 90,
                                        height: 80,
                                        color: isDark
                                            ? Colors.grey[800]
                                            : Colors.grey[200],
                                        child: const Icon(Icons.image,
                                            color: Colors.grey),
                                      ),
                              ),
                            ),
                            // Shipment status label for bought products (under image)
                            if (!widget.isSold &&
                                statusColor != null &&
                                statusText != null &&
                                statusIcon != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  width: 90,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: statusColor.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        statusIcon,
                                        size: 10,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 2),
                                      Flexible(
                                        child: Text(
                                          statusText,
                                          style: GoogleFonts.inter(
                                            color: statusColor,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 4),
                        // Right column: Product details
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${price.toStringAsFixed(2)} $currency',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.orangeAccent
                                        : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (quantity > 1) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A86B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'x$quantity',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF00A86B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Icon(
                        Icons.chevron_right,
                        color: const Color(0xFF00A86B),
                        size: 24,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategorizedTransactionsList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF00A86B),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ..._categorizedTransactions.expand((dateGroup) => [
                // Date header
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color.fromARGB(255, 45, 42, 65)
                          : const Color.fromARGB(255, 248, 249, 250),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? const Color.fromARGB(255, 60, 57, 78)
                            : const Color.fromARGB(255, 230, 232, 236),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          dateGroup.date,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Seller groups for this date
                ...dateGroup.sellerGroups.expand((sellerGroup) => [
                      // Seller header
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(24, 8, 12, 4),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF00A86B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.store_rounded,
                                  size: 16,
                                  color: const Color(0xFF00A86B),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  sellerGroup.sellerName,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF00A86B),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF00A86B).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${sellerGroup.transactions.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF00A86B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Products for this seller
                      SliverPadding(
                        padding: const EdgeInsets.only(
                            left: 24, right: 12, bottom: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildTransactionItem(
                                sellerGroup.transactions[index]),
                            childCount: sellerGroup.transactions.length,
                          ),
                        ),
                      ),
                    ]),
              ]),

          // Loading indicator at the bottom
          if (_loadingMore && !_isSearchMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? Colors.tealAccent : Colors.teal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    // For bought products, use categorized view
    if (!widget.isSold) {
      return _buildCategorizedTransactionsList();
    }

    // For sold products, use the original flat list
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF00A86B),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _filteredTransactions.length) {
                    if (_loadingMore && !_isSearchMode) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.tealAccent : Colors.teal,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final tx = _filteredTransactions[index];
                  return _buildTransactionItem(tx);
                },
                childCount: _filteredTransactions.length +
                    ((_loadingMore && !_isSearchMode) ? 1 : 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTransactionTap(Map<String, dynamic> data, String tid) {
    final orderId = data['orderId'] as String?;

    if (orderId == null) {
      _showErrorSnackBar('Unable to find order details');
      return;
    }

    if (widget.isSold) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SoldProductsScreen(orderId: orderId),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShipmentStatusScreen(orderId: orderId),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final l10n = AppLocalizations.of(context);
    final user = _auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return _buildLoginPrompt(l10n);
    }

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1A29) : null,
          gradient: isDark
              ? null
              : LinearGradient(
                  colors: [Colors.grey[100]!, Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
        ),
        child: Builder(
          builder: (context) {
            if (_errorMessage != null) {
              return _buildErrorWidget();
            }

            if (_isLoadingInitial) {
              return _buildShimmerList();
            }

            if (_isSearchMode) {
              return _buildSearchResults();
            }

            if (_filteredTransactions.isEmpty) {
              return _buildEmptyState(l10n);
            }

            return _buildTransactionsList();
          },
        ),
      ),
    );
  }
}
