import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../widgets/myproducts/sold_bought_products_tab.dart';
import 'package:provider/provider.dart';
import '../../providers/my_products_provider.dart';
import 'package:go_router/go_router.dart';

// =============================================================================
// PENDING ORDER BANNER STATE
// =============================================================================

enum _PendingBannerState {
  none,
  processing, // payment received, order being created
  succeeded,  // order created successfully
  failed,     // payment_succeeded_order_failed — ops notified
}

// =============================================================================
// ENTRY POINT
// =============================================================================

class MyOrdersScreen extends StatefulWidget {
  /// Passed when the payment callback returned 'processing' — order not yet
  /// created. Orders screen owns the wait and resolves via Firestore listener.
  final String? pendingOrderNumber;

  /// Passed when the server already created the order (fast path via
  /// payment-success:// deep link). Just show a brief success banner.
  final String? pendingOrderId;

  const MyOrdersScreen({
    Key? key,
    this.pendingOrderNumber,
    this.pendingOrderId,
  }) : super(key: key);

  @override
  _MyOrdersScreenState createState() => _MyOrdersScreenState();
}

// =============================================================================
// STATE
// =============================================================================

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
  bool _isTabSyncing = false;

  // ── Pending order resolution ───────────────────────────────────────────────
  _PendingBannerState _bannerState = _PendingBannerState.none;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pendingOrderSub;
  Timer? _bannerDismissTimer;

  // ── Orders provider (owned by this screen) ─────────────────────────────────
  // Owned here (not created in build) so: (1) the calendar AppBar action can
  // reach it via a stable reference, and (2) we can listen for date-range
  // changes and refresh the already-loaded tabs.
  late final MyProductsProvider _ordersProvider;
  DateTimeRange? _activeDateRange;

  // =============================================================================
  // LIFECYCLE
  // =============================================================================

  @override
  void initState() {
    super.initState();
    _ordersProvider = MyProductsProvider();
    _ordersProvider.addListener(_onOrdersProviderChanged);

    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();
    _tabController.addListener(_handleTabChange);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChange);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _initPendingOrder();
  }

  /// Fires on every provider notification. We only react to date-range
  /// transitions (equality check below) to avoid re-fetching on unrelated
  /// notifications like search query updates.
  void _onOrdersProviderChanged() {
    final current = _ordersProvider.selectedDateRange;
    if (current == _activeDateRange) return;
    _activeDateRange = current;
    if (!mounted) return;
    setState(() {}); // refresh AppBar icon state + filter chip
    _refreshLoadedTabs();
  }

  /// Reset pagination on both tabs whose data is already on screen.
  /// The lazy sold tab is skipped until the user actually opens it —
  /// ensureLoaded() will pick up the current date range at that point.
  void _refreshLoadedTabs() {
    _boughtTabKey.currentState?.refresh();
    final sold = _soldTabKey.currentState;
    if (sold != null && sold.hasStartedLoading) {
      sold.refresh();
    }
  }

  /// Wire up the pending order state depending on which param was passed.
  void _initPendingOrder() {
    if (widget.pendingOrderNumber != null) {
      // Payment received but order not yet created — listen for resolution.
      _bannerState = _PendingBannerState.processing;
      _listenToPendingOrder(widget.pendingOrderNumber!);
      // Bought tab is already at index 0 (default) — no tab switch needed.
    } else if (widget.pendingOrderId != null) {
      // Order already created (fast path) — show brief success banner.
      _bannerState = _PendingBannerState.succeeded;
      // Bought tab is already at index 0 (default) — no tab switch needed.
      _refreshBoughtTab();
      _scheduleBannerDismiss();
    }
  }

  @override
  void dispose() {
    _ordersProvider.removeListener(_onOrdersProviderChanged);
    _ordersProvider.dispose();
    _tabController.removeListener(_handleTabChange);
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _tabController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _pendingOrderSub?.cancel();
    _bannerDismissTimer?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  // =============================================================================
  // PENDING ORDER LISTENER
  // =============================================================================

  void _listenToPendingOrder(String orderNumber) {
    _pendingOrderSub = FirebaseFirestore.instance
        .collection('pendingPayments')
        .doc(orderNumber)
        .snapshots()
        .listen(
      (snap) {
        if (!snap.exists || !mounted) return;
        final status = snap.data()?['status'] as String?;

        if (status == 'completed') {
          _pendingOrderSub?.cancel();
          setState(() => _bannerState = _PendingBannerState.succeeded);
          _refreshBoughtTab();
          _scheduleBannerDismiss();
        } else if (status == 'payment_succeeded_order_failed') {
          // Ops team has been alerted. Surface a gentle message; no retry.
          _pendingOrderSub?.cancel();
          setState(() => _bannerState = _PendingBannerState.failed);
          // Keep failed banner visible — don't auto-dismiss.
        }
        // 'payment_failed' won't appear here (user already paid and we
        // navigated here), but guard defensively.
        else if (status == 'payment_failed' ||
            status == 'hash_verification_failed') {
          _pendingOrderSub?.cancel();
          setState(() => _bannerState = _PendingBannerState.failed);
        }
      },
      onError: (Object e) {
        debugPrint('[MyOrders] Pending order listener error: $e');
      },
    );
  }

  // =============================================================================
  // TAB / BANNER HELPERS
  // =============================================================================

  void _switchToBoughtTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabController.index == 0) return;
      _isTabSyncing = true;
      _tabController.animateTo(0);
      _pageController
          .animateToPage(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
          )
          .then((_) => _isTabSyncing = false);
    });
  }

  void _refreshBoughtTab() {
    // Post-frame to ensure the tab's State is mounted after any navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boughtTabKey.currentState?.refresh();
    });
  }

  void _scheduleBannerDismiss() {
    _bannerDismissTimer?.cancel();
    _bannerDismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _bannerState = _PendingBannerState.none);
    });
  }

  // =============================================================================
  // TAB / SEARCH HANDLERS
  // =============================================================================

  void _handleTabChange() {
    if (_tabController.indexIsChanging && !_isTabSyncing) {
      _isTabSyncing = true;
      _pageController
          .animateToPage(
            _tabController.index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
          )
          .then((_) => _isTabSyncing = false);
    }
  }

  void _onSearchFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      FocusScope.of(context).unfocus();
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      if (_currentSearchQuery != query) {
        setState(() => _currentSearchQuery = query);
        _applySearchToAllTabs();
      }
    });
  }

  void _applySearchToAllTabs() {
    _soldTabKey.currentState?.applySearch(_currentSearchQuery);
    _boughtTabKey.currentState?.applySearch(_currentSearchQuery);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _currentSearchQuery = '');
    _applySearchToAllTabs();
  }

  void _dismissKeyboard() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    }
  }

  // =============================================================================
  // DATE PICKER
  // =============================================================================

  Future<void> _pickDateRange() async {
    _dismissKeyboard();

    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final backgroundColor = isLight ? Colors.white : Colors.grey[900]!;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _ordersProvider.selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
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
            ),
            dialogTheme: DialogThemeData(backgroundColor: backgroundColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _ordersProvider.updateSelectedDateRange(picked);
    }
  }

  void _clearDateRange() {
    _ordersProvider.updateSelectedDateRange(null);
  }

  Widget _buildDateFilterChip() {
    final range = _ordersProvider.selectedDateRange;
    if (range == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fmt = DateFormat('dd MMM yyyy');
    final label = '${fmt.format(range.start)}  –  ${fmt.format(range.end)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: jadeGreen.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: jadeGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 16, color: jadeGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: jadeGreen,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _clearDateRange,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 16, color: jadeGreen),
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================================
  // PENDING ORDER BANNER WIDGET
  // =============================================================================

  Widget _buildPendingOrderBanner() {
    if (_bannerState == _PendingBannerState.none) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _bannerState == _PendingBannerState.none
          ? const SizedBox.shrink()
          : _PendingBannerContent(
              key: ValueKey(_bannerState),
              state: _bannerState,
              isDark: isDark,
              onDismiss: _bannerState == _PendingBannerState.failed
                  ? () => setState(() => _bannerState = _PendingBannerState.none)
                  : null,
            ),
    );
  }

  // =============================================================================
  // TAB BAR
  // =============================================================================

  Widget _buildModernTabBar() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
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
              color: const Color(0xFF00A86B).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        indicatorSize: TabBarIndicatorSize.tab,
        onTap: (index) {
          _dismissKeyboard();
          // Trigger lazy load when the sold tab (index 1) is tapped.
          if (index == 1) {
            _soldTabKey.currentState?.ensureLoaded();
          }
          if (_currentSearchQuery.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 100), () {
              _applySearchToAllTabs();
            });
          }
        },
        tabs: [
          _buildModernTab(l10n.boughtProducts, Icons.shopping_cart_rounded),
          _buildModernTab(l10n.soldProducts, Icons.sell_rounded),
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
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================================================================
  // SEARCH BOX
  // =============================================================================

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
          style: TextStyle(
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
            hintStyle: TextStyle(
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
            if (!_searchFocusNode.hasFocus) {
              _searchFocusNode.requestFocus();
            }
          },
          onSubmitted: (_) => _dismissKeyboard(),
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
          tooltip: AppLocalizations.of(context).clearSearch,
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

  // =============================================================================
  // BUILD
  // =============================================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasDateFilter = _ordersProvider.selectedDateRange != null;

    return ChangeNotifierProvider<MyProductsProvider>.value(
      value: _ordersProvider,
      child: GestureDetector(
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
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
            title: Text(
              l10n.myOrders,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.date_range_rounded,
                  color: hasDateFilter
                      ? jadeGreen
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                onPressed: _pickDateRange,
                tooltip: AppLocalizations.of(context).filterByDateRange,
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
                _buildSearchBox(),
                // ── Pending order banner ─────────────────────────────────────
                _buildPendingOrderBanner(),
                _buildDateFilterChip(),
                _buildModernTabBar(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      // Trigger lazy load when the sold tab (index 1) becomes visible.
                      if (index == 1) {
                        _soldTabKey.currentState?.ensureLoaded();
                      }

                      if (_tabController.index != index && !_isTabSyncing) {
                        _isTabSyncing = true;
                        _tabController.animateTo(index);
                        _dismissKeyboard();

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
                      SoldBoughtProductsTab(
                        key: _boughtTabKey,
                        isSold: false,
                      ),
                      SoldBoughtProductsTab(
                        key: _soldTabKey,
                        isSold: true,
                        lazyLoad: true,
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

// =============================================================================
// PENDING BANNER CONTENT
// =============================================================================
// Extracted as a stateful widget so only the banner re-renders on state changes,
// not the entire screen.

class _PendingBannerContent extends StatefulWidget {
  final _PendingBannerState state;
  final bool isDark;
  final VoidCallback? onDismiss;

  const _PendingBannerContent({
    super.key,
    required this.state,
    required this.isDark,
    this.onDismiss,
  });

  @override
  State<_PendingBannerContent> createState() => _PendingBannerContentState();
}

class _PendingBannerContentState extends State<_PendingBannerContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.state == _PendingBannerState.processing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PendingBannerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != _PendingBannerState.processing) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = _bannerConfig(widget.state, widget.isDark, l10n);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config.borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Icon / spinner
            if (widget.state == _PendingBannerState.processing)
              FadeTransition(
                opacity: _pulseAnimation,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(config.iconColor),
                  ),
                ),
              )
            else
              Icon(config.icon, size: 18, color: config.iconColor),

            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: config.titleColor,
                    ),
                  ),
                  if (config.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      config.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: config.subtitleColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Dismiss button (only for failed state)
            if (widget.onDismiss != null)
              GestureDetector(
                onTap: widget.onDismiss,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: config.iconColor.withOpacity(0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _BannerConfig _bannerConfig(_PendingBannerState state, bool isDark, AppLocalizations l10n) {
    switch (state) {
      case _PendingBannerState.processing:
        return _BannerConfig(
          backgroundColor: isDark
              ? const Color(0xFF2D2410)
              : const Color(0xFFFFFBEB),
          borderColor: const Color(0xFFF59E0B).withOpacity(0.4),
          iconColor: const Color(0xFFF59E0B),
          titleColor: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
          subtitleColor: isDark
              ? const Color(0xFFFCD34D).withOpacity(0.7)
              : const Color(0xFF92400E).withOpacity(0.7),
          icon: Icons.hourglass_top_rounded,
          title: l10n.processingPayment,
          subtitle: l10n.orderWillAppearAutomatically,
        );
      case _PendingBannerState.succeeded:
        return _BannerConfig(
          backgroundColor: isDark
              ? const Color(0xFF0D2818)
              : const Color(0xFFECFDF5),
          borderColor: const Color(0xFF00A86B).withOpacity(0.4),
          iconColor: const Color(0xFF00A86B),
          titleColor: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46),
          subtitleColor: isDark
              ? const Color(0xFF34D399).withOpacity(0.7)
              : const Color(0xFF065F46).withOpacity(0.7),
          icon: Icons.check_circle_rounded,
          title: l10n.orderPlacedSuccessfully,
          subtitle: null,
        );
      case _PendingBannerState.failed:
        return _BannerConfig(
          backgroundColor: isDark
              ? const Color(0xFF2D1010)
              : const Color(0xFFFEF2F2),
          borderColor: Colors.red.withOpacity(0.4),
          iconColor: Colors.red,
          titleColor: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
          subtitleColor: isDark
              ? const Color(0xFFFCA5A5).withOpacity(0.7)
              : const Color(0xFF991B1B).withOpacity(0.7),
          icon: Icons.info_outline_rounded,
          title: l10n.paymentReceivedTeamNotified,
          subtitle: l10n.orderWillBeResolvedShortly,
        );
      case _PendingBannerState.none:
        // Should never render in none state
        return _BannerConfig(
          backgroundColor: Colors.transparent,
          borderColor: Colors.transparent,
          iconColor: Colors.transparent,
          titleColor: Colors.transparent,
          subtitleColor: Colors.transparent,
          icon: Icons.circle,
          title: '',
          subtitle: null,
        );
    }
  }
}

class _BannerConfig {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color titleColor;
  final Color subtitleColor;
  final IconData icon;
  final String title;
  final String? subtitle;

  const _BannerConfig({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.titleColor,
    required this.subtitleColor,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}