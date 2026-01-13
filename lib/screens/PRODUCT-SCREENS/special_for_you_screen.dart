import 'package:flutter/material.dart';
import '../../services/personalized_feed_service.dart';
import '../../../models/product.dart';
import '../../widgets/product_list_sliver.dart';
import '../../widgets/product_card_shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SpecialForYouScreen extends StatefulWidget {
  const SpecialForYouScreen({Key? key}) : super(key: key);

  @override
  State<SpecialForYouScreen> createState() => _SpecialForYouScreenState();
}

class _SpecialForYouScreenState extends State<SpecialForYouScreen>
    with AutomaticKeepAliveClientMixin {
  static const double _expandedHeight = 150.0;
  static const double _horizontalMargin = 16.0;
  static const int _batchSize = 30; // Firestore whereIn limit

  final PersonalizedFeedService _feedService = PersonalizedFeedService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();

  List<String> _allProductIds = []; // All 200 IDs from backend
  List<Product> _loadedProducts = []; // Products loaded so far
  int _currentIndex = 0; // Current position in _allProductIds

  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
    _scrollController.addListener(_onScroll);
  }

  /// Initial load: Get all 200 IDs and load first batch
  Future<void> _initialize() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
    });

    try {
      // Get all 200 product IDs from service
      _allProductIds = await _feedService.getProductIds();

      if (_allProductIds.isEmpty) {
        setState(() {
          _hasMore = false;
          _isInitialLoading = false;
        });
        return;
      }

      // Load first batch (30 products)
      await _loadNextBatch();
    } catch (e) {
      debugPrint('Error initializing special for you: $e');
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  /// Load next batch of products (30 at a time)
  Future<void> _loadNextBatch() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Calculate how many IDs are left
      final remainingIds = _allProductIds.length - _currentIndex;

      if (remainingIds <= 0) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      // Get next batch of IDs (max 30 for Firestore whereIn)
      final batchSize = remainingIds < _batchSize ? remainingIds : _batchSize;
      final nextBatch = _allProductIds.sublist(
        _currentIndex,
        _currentIndex + batchSize,
      );

      // Fetch product details from Firestore
      final products = await _fetchProductDetails(nextBatch);

      if (mounted) {
        setState(() {
          _loadedProducts.addAll(products);
          _currentIndex += batchSize;
          _hasMore = _currentIndex < _allProductIds.length;
          _isLoadingMore = false;
        });
      }

      debugPrint(
        'Loaded batch: ${products.length} products '
        '(${_loadedProducts.length}/${_allProductIds.length} total)',
      );
    } catch (e) {
      debugPrint('Error loading batch: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).errorLoadingProducts ??
                  'Error loading products',
            ),
          ),
        );
      }
    }
  }

  /// Fetch product details from Firestore in a single query
  Future<List<Product>> _fetchProductDetails(List<String> productIds) async {
    if (productIds.isEmpty) return [];

    final snapshot = await _firestore
        .collection('shop_products')
        .where(FieldPath.documentId, whereIn: productIds)
        .get();

    final products = <Product>[];
    for (final doc in snapshot.docs) {
      try {
        products.add(Product.fromDocument(doc));
      } catch (e) {
        debugPrint('Error parsing product ${doc.id}: $e');
      }
    }

    // Maintain order from productIds
    final productMap = {for (var p in products) p.id: p};
    return productIds
        .where((id) => productMap.containsKey(id))
        .map((id) => productMap[id]!)
        .toList();
  }

  /// Infinite scroll listener
  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;

    final threshold = _scrollController.position.maxScrollExtent * 0.85;
    if (_scrollController.position.pixels >= threshold) {
      _loadNextBatch();
    }
  }

  /// Pull-to-refresh
  Future<void> _refresh() async {
    // Force refresh from backend
    await _feedService.forceRefresh();

    // Reset state
    setState(() {
      _allProductIds.clear();
      _loadedProducts.clear();
      _currentIndex = 0;
      _hasMore = true;
      _error = null;
    });

    // Reload
    await _initialize();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        child: _buildBody(context, l10n, isLightMode, statusBarHeight),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    bool isLightMode,
    double statusBarHeight,
  ) {
    // Show loading on initial fetch
    if (_isInitialLoading) {
      return CustomScrollView(
        slivers: [
          _buildAppBar(l10n, isLightMode, statusBarHeight),
          SliverPadding(
            padding: const EdgeInsets.all(12.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.58,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => const ProductCardShimmer(
                  portraitImageHeight: 180,
                ),
                childCount: 6,
              ),
            ),
          ),
        ],
      );
    }

    // Show error state
    if (_error != null && _loadedProducts.isEmpty) {
      return CustomScrollView(
        slivers: [
          _buildAppBar(l10n, isLightMode, statusBarHeight),
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    l10n.errorLoadingProducts ?? 'Error loading products',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retry ?? 'Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Show empty state
    if (_loadedProducts.isEmpty) {
      return CustomScrollView(
        slivers: [
          _buildAppBar(l10n, isLightMode, statusBarHeight),
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noRecommendationsYet ?? 'No recommendations yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.startBrowsingToGetRecommendations ??
                        'Start browsing to get personalized recommendations',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Show products with pull-to-refresh
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          _buildAppBar(l10n, isLightMode, statusBarHeight),
          ProductListSliver(
            products: _loadedProducts,
            boostedProducts: const [],
            hasMore: _hasMore,
            screenName: 'special_for_you_screen',
            isLoadingMore: _isLoadingMore,
            selectedColor: null,
          ),
          // Show shimmer cards at bottom when loading more
          if (_isLoadingMore)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.58,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const ProductCardShimmer(
                    portraitImageHeight: 180,
                  ),
                  childCount: 2,
                ),
              ),
            ),
          // Show "End of recommendations" message
          if (!_hasMore && _loadedProducts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.pullToRefresh ?? 'Pull down to refresh',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(
    AppLocalizations l10n,
    bool isLightMode,
    double statusBarHeight,
  ) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: _expandedHeight + statusBarHeight,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        titlePadding: EdgeInsets.zero,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.orange, Colors.pink],
            ),
          ),
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final currentHeight = constraints.maxHeight;
            double fraction = (currentHeight - kToolbarHeight) /
                (_expandedHeight - kToolbarHeight + statusBarHeight);
            fraction = fraction.clamp(0.0, 1.0);
            final collapseRatio = 1 - fraction;
            final collapsedLeft = kToolbarHeight + _horizontalMargin;
            final leftPadding =
                _horizontalMargin * fraction + collapsedLeft * collapseRatio;
            final textColor = isLightMode
                ? Color.lerp(Colors.white, Colors.black, collapseRatio)!
                : Colors.white;
            return Padding(
              padding: EdgeInsetsDirectional.only(
                start: leftPadding,
                bottom: _horizontalMargin,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.specialProductsForYou,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ),
                  // Show count badge when products are loaded
                  if (_loadedProducts.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_loadedProducts.length}/${_allProductIds.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
