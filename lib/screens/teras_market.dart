import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/teras_provider.dart';
import '../providers/teras_product_list_provider.dart';
import '../widgets/terasmarket/teras_filter_sort_row.dart';
import '../widgets/terasmarket/teras_preference_product.dart';
import '../widgets/market_banner.dart';
import '../widgets/terasmarket/teras_product_list.dart';

class TerasMarket extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final Future<void> Function() onSubmitSearch;
  const TerasMarket({
    Key? key,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSubmitSearch,
  }) : super(key: key);
  @override
  TerasMarketState createState() => TerasMarketState();
}

class TerasMarketState extends State<TerasMarket> {
  // Controllers
  late final ScrollController _scrollController;
  late final ScrollController _filterScrollController;

  // Providers
  late final TerasProvider _terasProvider;
  late final TerasProductListProvider _homeProductProvider;

  @override
  void initState() {
    super.initState();
    // Initialize providers
    _terasProvider = Provider.of<TerasProvider>(context, listen: false);
    _homeProductProvider = TerasProductListProvider();

    // Initialize controllers
    _scrollController = ScrollController();
    _filterScrollController = ScrollController();

    // Initialize data after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeProductProvider.initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _filterScrollController.dispose();
    _homeProductProvider.dispose();
    super.dispose();
  }

  /// Unfocus keyboard
  void _unfocusKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }
  }

  /// Build home content with provider
  Widget _buildHomeContent() {
    return ChangeNotifierProvider<TerasProductListProvider>.value(
      value: _homeProductProvider,
      child: Builder(
        builder: (context) {
          final provider = context.read<TerasProductListProvider>();
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final isTabletLandscape =
              screenWidth >= 600 && screenWidth > screenHeight;
          // Tablet landscape: increased spacing to prevent info area overlap
          final preferenceSpacing = isTabletLandscape ? 48.0 : 20.0;

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                _terasProvider.onRefresh(),
                provider.refresh(),
              ]);
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification) {
                  final maxScroll = notification.metrics.maxScrollExtent;
                  final currentScroll = notification.metrics.pixels;
                  final threshold = maxScroll * 0.85;

                  if (currentScroll >= threshold) {
                    provider.loadMore();
                  }
                }
                return false;
              },
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  const SliverToBoxAdapter(child: TerasPreferenceProduct()),
                  SliverToBoxAdapter(
                      child: SizedBox(height: preferenceSpacing)),
                  const TerasProductList(),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  const MarketBannerSliver(),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _unfocusKeyboard,
        child: Column(
          children: [
            TerasFilterSortRow(
              scrollController: _filterScrollController,
            ),
            Expanded(
              child: _buildHomeContent(),
            ),
          ],
        ),
      ),
    );
  }
}
