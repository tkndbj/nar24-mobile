import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/myproducts/sold_bought_products_tab.dart';
import 'package:provider/provider.dart';
import '../../providers/my_products_provider.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({Key? key}) : super(key: key);

  @override
  _MyOrdersScreenState createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen>
    with TickerProviderStateMixin {
  static const Color jadeGreen = Color(0xFF00A86B);

  late TabController _tabController;
  late PageController _pageController;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _currentSearchQuery = '';
  Timer? _searchDebounce;

  // Keys to communicate with child widgets
  final GlobalKey<SoldBoughtProductsTabState> _soldTabKey = GlobalKey();
  final GlobalKey<SoldBoughtProductsTabState> _boughtTabKey = GlobalKey();

  // Track if tabs are syncing to prevent infinite loops
  bool _isTabSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();

    // Sync tab controller with page controller
    _tabController.addListener(_handleTabChange);

    // Setup search listener
    _searchController.addListener(_onSearchChanged);

    // Setup focus listener for search
    _searchFocusNode.addListener(_onSearchFocusChange);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging && !_isTabSyncing) {
      _isTabSyncing = true;
      _pageController
          .animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
      )
          .then((_) {
        _isTabSyncing = false;
      });
    }
  }

  void _onSearchFocusChange() {
    // This helps with focus management but the main solution is in GestureDetector
    if (!_searchFocusNode.hasFocus) {
      // Additional cleanup when focus is lost
      FocusScope.of(context).unfocus();
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      if (_currentSearchQuery != query) {
        setState(() {
          _currentSearchQuery = query;
        });
        _applySearchToAllTabs();
      }
    });
  }

  void _applySearchToAllTabs() {
    // Apply search to both tabs to maintain consistency
    _soldTabKey.currentState?.applySearch(_currentSearchQuery);
    _boughtTabKey.currentState?.applySearch(_currentSearchQuery);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _currentSearchQuery = '';
    });
    // Reset both tabs to show all data
    _applySearchToAllTabs();
  }

  void _dismissKeyboard() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _tabController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    // Dismiss keyboard when opening date picker
    _dismissKeyboard();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final backgroundColor = isLight ? Colors.white : Colors.grey[900]!;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: Provider.of<MyProductsProvider>(context, listen: false)
              .selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: jadeGreen,
              onPrimary: Colors.white,
              surface: backgroundColor,
              onSurface: theme.colorScheme.onSurface,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: isLight ? Colors.black : Colors.white,
              ),
            ), dialogTheme: DialogThemeData(backgroundColor: backgroundColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      Provider.of<MyProductsProvider>(context, listen: false)
          .updateSelectedDateRange(picked);
    }
  }

  Widget _buildModernTabBar() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,  // ← CHANGED: Makes tabs fill available width
        // tabAlignment removed - not needed when isScrollable is false
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00A86B), Color(0xFF00C574)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00A86B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        onTap: (index) {
          // Dismiss keyboard when switching tabs
          _dismissKeyboard();

          // Apply current search to newly selected tab after a brief delay
          if (_currentSearchQuery.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 100), () {
              _applySearchToAllTabs();
            });
          }
        },
        tabs: [
          _buildModernTab(l10n.soldProducts, Icons.sell_rounded),
          _buildModernTab(l10n.boughtProducts, Icons.shopping_cart_rounded),
        ],
      ),
    );
  }

  Widget _buildModernTab(String text, IconData icon) {
    return Tab(
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withOpacity(0.2)
            : Colors.white.withOpacity(0.8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
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
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            prefixIcon: Container(
              margin: const EdgeInsets.all(8),
              child: Icon(
                Icons.search_rounded,
                size: 18,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            suffixIcon: _buildSuffixIcon(isDark),
            hintText: l10n.searchOrders,
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
          onTap: () {
            // Ensure proper focus behavior
            if (!_searchFocusNode.hasFocus) {
              _searchFocusNode.requestFocus();
            }
          },
          onSubmitted: (value) {
            // Dismiss keyboard when user presses enter
            _dismissKeyboard();
          },
        ),
      ),
    );
  }

  Widget _buildSuffixIcon(bool isDark) {
    if (_searchController.text.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.all(6),
        child: IconButton(
          icon: Icon(
            Icons.clear_rounded,
            size: 18,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          onPressed: _clearSearch,
          tooltip: 'Clear search',
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(6),
      child: Icon(
        Icons.tune_rounded,
        size: 16,
        color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChangeNotifierProvider(
      create: (_) => MyProductsProvider(),
      child: GestureDetector(
        // Dismiss keyboard when tapping outside the search field
        onTap: _dismissKeyboard,
        child: Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF1C1A29) : const Color(0xFFFAFAFA),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
            iconTheme: IconThemeData(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            title: Text(
              l10n.myOrders,
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.date_range_rounded,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                onPressed: _pickDateRange,
                tooltip: 'Filter by date range',
              ),
            ],
          ),
          body: Container(
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
            child: Column(
              children: [
                // Functional search box
                _buildSearchBox(),

                // Tab bar
                _buildModernTabBar(),

                // Tab content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(), // Smoother physics
                    onPageChanged: (index) {
                      if (_tabController.index != index && !_isTabSyncing) {
                        _isTabSyncing = true;
                        _tabController.animateTo(index);

                        // Dismiss keyboard when swiping
                        _dismissKeyboard();

                        // Apply current search to newly selected tab
                        if (_currentSearchQuery.isNotEmpty) {
                          Future.delayed(const Duration(milliseconds: 100), () {
                            _applySearchToAllTabs();
                          });
                        }

                        Future.delayed(const Duration(milliseconds: 250), () {
                          _isTabSyncing = false;
                        });
                      }
                    },
                    children: [
                      // Sold products tab
                      SoldBoughtProductsTab(
                        key: _soldTabKey,
                        isSold: true,
                      ),

                      // Bought products tab
                      SoldBoughtProductsTab(
                        key: _boughtTabKey,
                        isSold: false,
                      ),
                    ],
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