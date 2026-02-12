import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../../generated/l10n/app_localizations.dart';
import '../../widgets/sellerpanel/dashboard_tab.dart';
import '../../widgets/sellerpanel/products_tab.dart';
import '../../widgets/sellerpanel/stock_tab.dart';
import '../../widgets/sellerpanel/transactions_tab.dart';
import '../../widgets/sellerpanel/shipments_tab.dart';
import '../../widgets/sellerpanel/ads_tab.dart';
import '../../providers/seller_panel_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

class SellerPanel extends StatefulWidget {
  final int initialTabIndex;
  final String? initialShopId;
  const SellerPanel({
    Key? key,
    this.initialTabIndex = 0,
    this.initialShopId,
  }) : super(key: key);

  @override
  State<SellerPanel> createState() => _SellerPanelState();
}

class _SellerPanelState extends State<SellerPanel>
    with TickerProviderStateMixin {
  late Future<void> _initializationFuture;
  StreamSubscription<User?>? _authSubscription;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 6, vsync: this, initialIndex: widget.initialTabIndex);
    // Defer to next event loop tick to avoid notifyListeners during build phase
    _initializationFuture = Future(() => _initializeProvider());
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        final provider =
            Provider.of<SellerPanelProvider>(context, listen: false);
        provider.resetState();
        setState(() {
          _initializationFuture = _initializeProvider();
        });
      }
    }, onError: (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error: $error')),
        );
      }
    });
  }

  Future<void> _initializeProvider() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    await provider.initialize();

    if (widget.initialShopId != null &&
        provider.shops.any((s) => s.id == widget.initialShopId)) {
      await provider.switchShop(widget.initialShopId!);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildModernShopDropdown(SellerPanelProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6200).withOpacity(0.1),
            const Color(0xFFFF6200).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF6200).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showShopSelector(provider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6200).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.store_rounded,
                    size: 16,
                    color: Color(0xFFFF6200),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    provider.selectedShop != null
                        ? (provider.selectedShop!.data()
                                as Map<String, dynamic>)['name'] ??
                            'Unnamed Shop'
                        : AppLocalizations.of(context).noShopSelected,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFF6200),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: const Color(0xFFFF6200).withOpacity(0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Checks if the current user has only viewer role for the selected shop.
  bool _isCurrentUserViewer(SellerPanelProvider provider) {
    if (provider.selectedShop == null) return false;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return false;
    final shopData = provider.selectedShop!.data() as Map<String, dynamic>?;
    if (shopData == null) return false;
    final viewers = (shopData['viewers'] as List?)?.cast<String>() ?? [];
    return viewers.contains(currentUserId);
  }

  void _showShopSelector(SellerPanelProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppLocalizations.of(context).selectShop,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...provider.shops.map((shop) {
              final shopData = shop.data() as Map<String, dynamic>;
              final isSelected = provider.selectedShop?.id == shop.id;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFF6200).withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF6200).withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      provider.switchShop(shop.id);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFF6200)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.store_rounded,
                              size: 20,
                              color:
                                  isSelected ? Colors.white : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              shopData['name'] ?? 'Unnamed Shop',
                              style: GoogleFonts.inter(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color:
                                    isSelected ? const Color(0xFFFF6200) : null,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFFFF6200),
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
            SafeArea(
              top: false,
              child: const SizedBox(height: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationButton(SellerPanelProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<int>(
      valueListenable: provider.unreadNotificationCountNotifier,
      builder: (context, unreadCount, child) {
        return Container(
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _showNotificationsBottomSheet(provider),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      unreadCount > 0
                          ? Icons.notifications_rounded
                          : Icons.notifications_outlined,
                      color: unreadCount > 0
                          ? const Color(0xFFFF6200)
                          : (isDark ? Colors.white70 : Colors.grey[700]),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6200), Color(0xFFFF8534)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6200).withOpacity(0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showNotificationsBottomSheet(SellerPanelProvider provider) {
    if (provider.selectedShop == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShopNotificationsBottomSheet(
        shopId: provider.selectedShop!.id,
        tabController: _tabController,
      ),
    );
  }

  Widget _buildModernPopupMenu(SellerPanelProvider provider) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.withOpacity(0.1)
            : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showOptionsMenu(provider),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.more_vert_rounded,
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.grey[700]
                  : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionsMenu(SellerPanelProvider provider) {
    final isViewer = _isCurrentUserViewer(provider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                AppLocalizations.of(context).shopOptions,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Hide Shop Settings for viewers
            if (!isViewer)
              _buildMenuOption(
                icon: Icons.settings_rounded,
                title: AppLocalizations.of(context).shopSettings,
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                      '/seller_panel_shop_settings/${provider.selectedShop!.id}');
                },
              ),
            // Hide User Permissions for viewers
            if (!isViewer)
              _buildMenuOption(
                icon: Icons.people_rounded,
                title: AppLocalizations.of(context).userPermissions,
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                      '/seller_panel_user_permission/${provider.selectedShop!.id}');
                },
              ),
            _buildMenuOption(
              icon: Icons.help_outline_rounded,
              title: AppLocalizations.of(context).productQuestions,
              hasNotification: provider.hasUnansweredQuestions,
              notificationColor: Colors.green,
              onTap: () {
                Navigator.pop(context);
                context.push(
                    '/seller_panel_product_questions/${provider.selectedShop!.id}');
              },
            ),
            _buildMenuOption(
              icon: Icons.star_outline_rounded,
              title: AppLocalizations.of(context).reviews,
              hasNotification:
                  true, // You mentioned this always shows notification
              notificationColor: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                context
                    .push('/seller_panel_reviews/${provider.selectedShop!.id}');
              },
            ),
            _buildMenuOption(
              icon: Icons.analytics_rounded,
              title: AppLocalizations.of(context).reports,
              onTap: () {
                Navigator.pop(context);
                context
                    .push('/seller_panel_reports/${provider.selectedShop!.id}');
              },
            ),
            _buildMenuOption(
              icon: Icons.receipt_long_rounded,
              title: AppLocalizations.of(context).shopReceipts,
              onTap: () {
                Navigator.pop(context);
                context.push(
                    '/seller_panel_receipts/${provider.selectedShop!.id}');
              },
            ),
            SafeArea(
              top: false,
              child: const SizedBox(height: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool hasNotification = false,
    Color notificationColor = Colors.red,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                ),
                if (hasNotification)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: notificationColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernTabBar(SellerPanelProvider provider) {
    // Detect tablet for centering tabs
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.grey.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: isTablet ? TabAlignment.center : TabAlignment.start,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)], // NEW COLORS
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color:
                  const Color(0xFF667EEA).withOpacity(0.3), // NEW SHADOW COLOR
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Theme.of(context).brightness == Brightness.light
            ? Colors.grey[600]
            : Colors.grey[400],
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
        tabs: [
          _buildModernTab(
              AppLocalizations.of(context).dashboard, Icons.dashboard_rounded),
          _buildModernTab(
              AppLocalizations.of(context).products, Icons.inventory_2_rounded),
          _buildModernTab(
            AppLocalizations.of(context).stock,
            Icons.warehouse_rounded,
          ),
          _buildModernTab(
            AppLocalizations.of(context).transactions,
            Icons.receipt_long_rounded,
          ),
          _buildModernTab(AppLocalizations.of(context).shipments,
              Icons.local_shipping_rounded),
          _buildModernTab(
              AppLocalizations.of(context).ads, Icons.campaign_rounded),
        ],
      ),
    );
  }

  Widget _buildModernTab(
    String text,
    IconData icon, {
    bool hasNotification = false,
    Color notificationColor = Colors.red,
  }) {
    return Tab(
      height: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(text),
              ],
            ),
            if (hasNotification)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: notificationColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final baseColor = isDark
              ? const Color.fromARGB(255, 40, 37, 58)
              : Colors.grey.shade300;
          final highlightColor = isDark
              ? const Color.fromARGB(255, 60, 57, 78)
              : Colors.grey.shade100;

          return Scaffold(
            body: Shimmer.fromColors(
              baseColor: baseColor,
              highlightColor: highlightColor,
              child: Column(
                children: [
                  Container(height: kToolbarHeight, color: baseColor),
                  Container(
                    height: 48,
                    color: baseColor,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: Alignment.centerLeft,
                    child: Container(height: 16, width: 120, color: baseColor),
                  ),
                  Container(
                    height: 48,
                    color: baseColor,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(
                            color: baseColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${AppLocalizations.of(context).initializationFailed}: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      setState(() {
                        _initializationFuture = _initializeProvider();
                      });
                    },
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ],
              ),
            ),
          );
        }

        return Consumer<SellerPanelProvider>(
          builder: (context, provider, child) {
            if (FirebaseAuth.instance.currentUser == null) {
              return Scaffold(
                body: Center(
                  child: Text(AppLocalizations.of(context).pleaseLogin),
                ),
              );
            }

            // Handle tab switch requests from other tabs
            if (provider.requestedTabIndex != null) {
              final targetIndex = provider.requestedTabIndex!;
              provider.clearRequestedTabIndex();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_tabController.index != targetIndex &&
                    !_tabController.indexIsChanging &&
                    targetIndex >= 0 &&
                    targetIndex < _tabController.length) {
                  _tabController.animateTo(targetIndex);
                }
              });
            }

            return Scaffold(
              backgroundColor: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFFAFAFA)
                  : null,
              appBar: AppBar(
                // don't show GoRouter's implicit back‐arrow
                automaticallyImplyLeading: false,

                elevation: 0,
                backgroundColor:
                    Theme.of(context).brightness == Brightness.light
                        ? Colors.white
                        : null,
                centerTitle: true, // Make sure this is true

                // Leading widget (back button)
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      // fallback if somehow there is nothing to pop
                      context.go('/');
                    }
                  },
                ),

                // Centered title
                title:
                    (provider.isLoadingShops || provider.selectedShop == null)
                        ? const _AppBarTitleShimmer()
                        : _buildModernShopDropdown(provider),

                // Actions to balance the leading widget
                actions: [
                  if (provider.selectedShop != null) ...[
                    _buildNotificationButton(provider),
                    _buildModernPopupMenu(provider),
                  ] else
                    const _ActionShimmer(), // keeps visual symmetry with leading icon
                ],

                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child:
                      (provider.isLoadingShops || provider.selectedShop == null)
                          ? const _TabBarShimmer()
                          : _buildModernTabBar(provider),
                ),
              ),
              body: SafeArea(
                top: false,
                child: (provider.selectedShop == null || provider.isLoadingShops)
                    ? _ShimmerBodySkeleton()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          DashboardTab(),
                          ProductsTab(),
                          StockTab(),
                          TransactionsTab(),
                          ShipmentsTab(),
                          AdsTab(),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ShimmerBodySkeleton extends StatelessWidget {
  const _ShimmerBodySkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color.fromARGB(255, 40, 37, 58) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 60, 57, 78) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: [
          // AppBar altındaki shop dropdown yerine bar iskeleti
          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // Tab bar iskeleti
          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 8),
          // İçerik ızgarası iskeleti
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(8),
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

class _AppBarTitleShimmer extends StatelessWidget {
  const _AppBarTitleShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        height: 20,
        width: 160,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _ActionShimmer extends StatelessWidget {
  const _ActionShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _TabBarShimmer extends StatelessWidget {
  const _TabBarShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: highlight,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet widget for displaying shop notifications with pagination
class _ShopNotificationsBottomSheet extends StatefulWidget {
  final String shopId;
  final TabController? tabController;

  const _ShopNotificationsBottomSheet({
    required this.shopId,
    this.tabController,
  });

  @override
  State<_ShopNotificationsBottomSheet> createState() =>
      _ShopNotificationsBottomSheetState();
}

class _ShopNotificationsBottomSheetState
    extends State<_ShopNotificationsBottomSheet> {
  static const int _pageSize = 20;
  bool _hasMarkedAsRead = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<DocumentSnapshot> _notifications = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNotifications();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await _firestore
          .collection('shop_notifications')
          .where('shopId', isEqualTo: widget.shopId)
          .orderBy('timestamp', descending: true)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _notifications = snapshot.docs;
        _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoading = false;
      });

      // ✅ ADD HERE - Mark all as read after successful load
      if (_notifications.isNotEmpty && !_hasMarkedAsRead) {
        _markAllVisibleAsRead();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllVisibleAsRead() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _hasMarkedAsRead = true;

    // Find unread notifications
    final unreadDocs = _notifications.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final isReadMap = data['isRead'] as Map<String, dynamic>? ?? {};
      return isReadMap[currentUserId] != true;
    }).toList();

    if (unreadDocs.isEmpty) {
      debugPrint('📖 No unread notifications to mark');
      return;
    }

    debugPrint('📖 Marking ${unreadDocs.length} notifications as read');

    try {
      final batch = _firestore.batch();
      for (final doc in unreadDocs) {
        batch.update(doc.reference, {
          'isRead.$currentUserId': true,
        });
      }
      await batch.commit();
      debugPrint('✅ All visible notifications marked as read');

      // Provider's real-time listener will update the badge count automatically
      // No need to refetch - just trigger rebuild to update UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error marking notifications as read: $e');
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (!mounted || _isLoadingMore || !_hasMore || _lastDocument == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snapshot = await _firestore
          .collection('shop_notifications') // ✅ Root collection
          .where('shopId', isEqualTo: widget.shopId) // ✅ Filter by shopId
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _notifications.addAll(snapshot.docs);
        _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  String _getLocalizedMessage(Map<String, dynamic> data, BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;

    switch (locale) {
      case 'tr':
        return data['message_tr'] as String? ??
            data['message'] as String? ??
            '';
      case 'ru':
        return data['message_ru'] as String? ??
            data['message'] as String? ??
            '';
      default:
        return data['message_en'] as String? ??
            data['message'] as String? ??
            '';
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return AppLocalizations.of(context).justNow;
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return DateFormat.MMMd(Localizations.localeOf(context).languageCode)
          .format(date);
    }
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'product_sold':
      case 'order':
        return Icons.shopping_bag_rounded;
      case 'review':
        return Icons.star_rounded;
      case 'question':
        return Icons.help_outline_rounded;
      case 'stock':
        return Icons.inventory_2_rounded;
      case 'payment':
        return Icons.payments_rounded;
      case 'shipment':
        return Icons.local_shipping_rounded;
      case 'campaign':
        return Icons.campaign_rounded;
      case 'boost':
        return Icons.rocket_launch_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getNotificationColor(String? type) {
    switch (type) {
      case 'product_sold':
      case 'order':
        return const Color(0xFF4CAF50);
      case 'review':
        return const Color(0xFFFFC107);
      case 'question':
        return const Color(0xFF2196F3);
      case 'stock':
        return const Color(0xFFFF5722);
      case 'payment':
        return const Color(0xFF9C27B0);
      case 'shipment':
        return const Color(0xFF00BCD4);
      case 'campaign':
        return const Color(0xFFE91E63);
      case 'boost':
        return const Color(0xFFFF6200);
      case 'warning':
        return const Color(0xFFFF9800);
      case 'info':
        return const Color(0xFF607D8B);
      default:
        return const Color(0xFF667EEA);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.75,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).shopNotifications,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white70 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Flexible(
            child: _buildContent(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return _buildLoadingState(isDark);
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return _buildNotificationsList(isDark);
  }

  Widget _buildLoadingState(bool isDark) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).errorLoadingNotifications,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadNotifications,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 48,
                color: isDark ? Colors.white38 : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noShopNotifications,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).noShopNotificationsDesc,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsList(bool isDark) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _notifications.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _notifications.length) {
          return _buildLoadingMoreIndicator();
        }

        final doc = _notifications[index];
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type'] as String?;
        final timestamp = data['timestamp'] as Timestamp?;

        // ✅ Fix isRead check
        final isReadMap = data['isRead'] as Map<String, dynamic>? ?? {};
        final isRead = isReadMap[currentUserId] == true;

        final message = _getLocalizedMessage(data, context);

        return _buildNotificationTile(
          type: type,
          message: message,
          timestamp: timestamp,
          isRead: isRead,
          isDark: isDark,
          docId: doc.id,
          data: data,
        );
      },
    );
  }

  void _handleNotificationTap(String? type, Map<String, dynamic> data) {
    final shopId = data['shopId'] as String?;

    // Capture references before popping
    final NavigatorState? navigator = Navigator.maybeOf(context);
    final GoRouter? router = GoRouter.maybeOf(context);
    final TabController? tabController = widget.tabController;

    // Guard: ensure navigator exists
    if (navigator == null) {
      debugPrint('⚠️ Navigator not found');
      return;
    }

    // Close bottom sheet
    navigator.pop();

    // Navigate after frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        switch (type) {
          case 'product_sold':
            _safeAnimateToTab(tabController, 3);
            break;
          case 'product_out_of_stock_seller_panel':
            _safeAnimateToTab(tabController, 2);
            break;
          case 'product_review_shop':
          case 'seller_review_shop':
            if (shopId != null && router != null) {
              router.push('/seller_panel_reviews/$shopId');
            }
            break;
          case 'product_question':
            if (shopId != null && router != null) {
              router.push('/seller_panel_product_questions/$shopId');
            }
            break;
          default:
            break;
        }
      } catch (e, stackTrace) {
        debugPrint('❌ Navigation error: $e\n$stackTrace');
      }
    });
  }

  /// Safely animate to a tab index with guards
  void _safeAnimateToTab(TabController? controller, int index) {
    if (controller == null) {
      debugPrint('⚠️ TabController is null');
      return;
    }

    // Check if controller is still usable
    if (controller.length == 0) {
      debugPrint('⚠️ TabController has no tabs');
      return;
    }

    // Validate index
    if (index < 0 || index >= controller.length) {
      debugPrint('⚠️ Invalid tab index: $index');
      return;
    }

    // Skip if already on target tab or currently animating
    if (controller.index == index || controller.indexIsChanging) {
      return;
    }

    controller.animateTo(index);
  }

  Widget _buildNotificationTile({
    required String? type,
    required String message,
    required Timestamp? timestamp,
    required bool isRead,
    required bool isDark,
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final iconColor = _getNotificationColor(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isRead
            ? Colors.transparent
            : (isDark
                ? iconColor.withOpacity(0.08)
                : iconColor.withOpacity(0.05)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.15),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _handleNotificationTap(type, data),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getNotificationIcon(type),
                    size: 20,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              isRead ? FontWeight.w400 : FontWeight.w500,
                          color: isDark ? Colors.white : Colors.grey[800],
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 12,
                            color: isDark ? Colors.white38 : Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTimestamp(timestamp),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.grey[500],
                            ),
                          ),
                          if (!isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: iconColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                AppLocalizations.of(context).newLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
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

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.white54
                  : Colors.grey[400]!,
            ),
          ),
        ),
      ),
    );
  }
}
