import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';
import 'dart:async';

/// Model for vitrin product applications
class VitrinProductApplication {
  final String id;
  final String? applicationId;
  final String productName;
  final String description;
  final double price;
  final int quantity;
  final String category;
  final String subcategory;
  final String subsubcategory;
  final String condition;
  final String? brandModel;
  final List<String> imageUrls;
  final String status; // pending, approved, rejected
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final String userId;
  final String? gender;
  final String? deliveryOption;
  final List<String>? availableColors;
  final Map<String, int>? colorQuantities;
  // For edit applications
  final String? editType;
  final String? originalProductId;
  final List<String>? editedFields;
  final bool isEditApplication;

  VitrinProductApplication({
    required this.id,
    this.applicationId,
    required this.productName,
    required this.description,
    required this.price,
    required this.quantity,
    required this.category,
    required this.subcategory,
    required this.subsubcategory,
    required this.condition,
    this.brandModel,
    required this.imageUrls,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.rejectionReason,
    required this.userId,
    this.gender,
    this.deliveryOption,
    this.availableColors,
    this.colorQuantities,
    this.editType,
    this.originalProductId,
    this.editedFields,
    this.isEditApplication = false,
  });

  factory VitrinProductApplication.fromDocument(
    DocumentSnapshot doc, {
    required bool isEdit,
  }) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      if (value is Map<String, dynamic> && value.containsKey('seconds')) {
        return DateTime.fromMillisecondsSinceEpoch(
          (value['seconds'] as int) * 1000,
        );
      }
      return DateTime.now();
    }

    return VitrinProductApplication(
      id: doc.id,
      applicationId: data['applicationId'] as String? ?? doc.id,
      productName:
          data['productName'] as String? ?? data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      price: (data['price'] is num)
          ? (data['price'] as num).toDouble()
          : double.tryParse(data['price']?.toString() ?? '0') ?? 0.0,
      quantity: (data['quantity'] is num)
          ? (data['quantity'] as num).toInt()
          : int.tryParse(data['quantity']?.toString() ?? '0') ?? 0,
      category: data['category'] as String? ?? '',
      subcategory: data['subcategory'] as String? ?? '',
      subsubcategory: data['subsubcategory'] as String? ?? '',
      condition: data['condition'] as String? ?? '',
      brandModel: data['brandModel'] as String? ?? data['brand'] as String?,
      imageUrls: (data['imageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      status: data['status'] as String? ?? 'pending',
      submittedAt: parseDate(
        isEdit
            ? (data['submittedAt'] ?? data['createdAt'])
            : (data['createdAt'] ?? data['submittedAt']),
      ),
      reviewedAt:
          data['reviewedAt'] != null ? parseDate(data['reviewedAt']) : null,
      rejectionReason: data['rejectionReason'] as String?,
      userId: data['userId'] as String? ?? '',
      gender: data['gender'] as String?,
      deliveryOption: data['deliveryOption'] as String?,
      availableColors: (data['availableColors'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      colorQuantities: (data['colorQuantities'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, (value as num).toInt())),
      editType: isEdit ? (data['editType'] as String? ?? 'product_edit') : null,
      originalProductId: data['originalProductId'] as String?,
      editedFields: (data['editedFields'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      isEditApplication: isEdit,
    );
  }
}

enum VitrinApplicationTab { all, pending, approved, rejected }

class VitrinPendingProductApplications extends StatefulWidget {
  const VitrinPendingProductApplications({super.key});

  @override
  State<VitrinPendingProductApplications> createState() =>
      _VitrinPendingProductApplicationsState();
}

class _VitrinPendingProductApplicationsState
    extends State<VitrinPendingProductApplications>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSubscription;
  String? _lastUserId;

  // Per-tab scroll controllers
  final Map<VitrinApplicationTab, ScrollController> _scrollControllers = {};

  // Per-tab data state for lazy loading
  final Map<VitrinApplicationTab, List<VitrinProductApplication>>
      _tabApplications = {};
  final Map<VitrinApplicationTab, bool> _tabIsLoading = {};
  final Map<VitrinApplicationTab, bool> _tabIsLoadingMore = {};
  final Map<VitrinApplicationTab, bool> _tabHasMore = {};
  final Map<VitrinApplicationTab, DocumentSnapshot?> _tabLastNewAppDoc = {};
  final Map<VitrinApplicationTab, DocumentSnapshot?> _tabLastEditAppDoc = {};
  final Map<VitrinApplicationTab, bool> _tabHasMoreNewApps = {};
  final Map<VitrinApplicationTab, bool> _tabHasMoreEditApps = {};

  // Track which tabs have been loaded (for lazy loading)
  final Set<VitrinApplicationTab> _loadedTabs = {};

  Map<VitrinApplicationTab, int> _counts = {
    VitrinApplicationTab.all: 0,
    VitrinApplicationTab.pending: 0,
    VitrinApplicationTab.approved: 0,
    VitrinApplicationTab.rejected: 0,
  };

  VitrinApplicationTab _activeTab = VitrinApplicationTab.all;
  static const int _pageSize = 10;

  String? get _currentUserId => _auth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Initialize per-tab state for all tabs
    for (final tab in VitrinApplicationTab.values) {
      _scrollControllers[tab] = ScrollController();
      _scrollControllers[tab]!.addListener(() => _onScroll(tab));
      _tabApplications[tab] = [];
      _tabIsLoading[tab] = false;
      _tabIsLoadingMore[tab] = false;
      _tabHasMore[tab] = true;
      _tabLastNewAppDoc[tab] = null;
      _tabLastEditAppDoc[tab] = null;
      _tabHasMoreNewApps[tab] = true;
      _tabHasMoreEditApps[tab] = true;
    }

    _lastUserId = _currentUserId;
    _setupAuthListener();
    _fetchCounts();
    // Load first tab (all) immediately
    _loadTabDataIfNeeded(VitrinApplicationTab.all);
  }

  void _setupAuthListener() {
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      final newUserId = user?.uid;

      // Only refresh if user actually changed (not just token refresh)
      if (newUserId != _lastUserId) {
        _lastUserId = newUserId;

        if (mounted) {
          // Reset all per-tab state
          setState(() {
            _loadedTabs.clear();
            for (final tab in VitrinApplicationTab.values) {
              _tabApplications[tab] = [];
              _tabLastNewAppDoc[tab] = null;
              _tabLastEditAppDoc[tab] = null;
              _tabHasMoreNewApps[tab] = true;
              _tabHasMoreEditApps[tab] = true;
              _tabHasMore[tab] = true;
              _tabIsLoading[tab] = false;
              _tabIsLoadingMore[tab] = false;
            }
            _counts = {
              VitrinApplicationTab.all: 0,
              VitrinApplicationTab.pending: 0,
              VitrinApplicationTab.approved: 0,
              VitrinApplicationTab.rejected: 0,
            };
          });

          if (newUserId != null) {
            _fetchCounts();
            _loadTabDataIfNeeded(_activeTab);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final newTab = VitrinApplicationTab.values[_tabController.index];
    if (newTab != _activeTab) {
      setState(() {
        _activeTab = newTab;
      });
      // Lazy load: only fetch data when tab is first visited
      _loadTabDataIfNeeded(newTab);
    }
  }

  void _onScroll(VitrinApplicationTab tab) {
    final controller = _scrollControllers[tab];
    if (controller == null || !controller.hasClients) return;

    if (controller.position.pixels >=
            controller.position.maxScrollExtent - 300 &&
        !(_tabIsLoadingMore[tab] ?? false) &&
        (_tabHasMore[tab] ?? false)) {
      _loadMoreApplications(tab);
    }
  }

  /// Lazy loading: only fetch data when tab is first visited
  void _loadTabDataIfNeeded(VitrinApplicationTab tab) {
    if (!_loadedTabs.contains(tab)) {
      _loadedTabs.add(tab);
      _fetchApplications(tab: tab);
    }
  }

  Future<void> _fetchCounts() async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      // Fetch from both collections
      final newAppsQuery = await _firestore
          .collection('vitrin_product_applications')
          .where('userId', isEqualTo: userId)
          .get();

      final editAppsQuery = await _firestore
          .collection('vitrin_product_edit_applications')
          .where('userId', isEqualTo: userId)
          .get();

      int pending = 0;
      int approved = 0;
      int rejected = 0;

      // Count new applications
      for (final doc in newAppsQuery.docs) {
        final status = doc.data()['status'] as String?;
        if (status == 'pending') {
          pending++;
        } else if (status == 'approved') {
          approved++;
        } else if (status == 'rejected') {
          rejected++;
        }
      }

      // Count edit applications
      for (final doc in editAppsQuery.docs) {
        final status = doc.data()['status'] as String?;
        if (status == 'pending') {
          pending++;
        } else if (status == 'approved') {
          approved++;
        } else if (status == 'rejected') {
          rejected++;
        }
      }

      if (mounted) {
        setState(() {
          _counts = {
            VitrinApplicationTab.all: pending + approved + rejected,
            VitrinApplicationTab.pending: pending,
            VitrinApplicationTab.approved: approved,
            VitrinApplicationTab.rejected: rejected,
          };
        });
      }
    } catch (e) {
      debugPrint('Error fetching counts: $e');
    }
  }

  Future<void> _fetchApplications({
    required VitrinApplicationTab tab,
    bool isLoadMore = false,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      setState(() {
        _tabIsLoading[tab] = false;
        _tabApplications[tab] = [];
      });
      return;
    }

    if (isLoadMore) {
      // Don't fetch if there's nothing more from either collection
      if (!(_tabHasMoreNewApps[tab] ?? false) &&
          !(_tabHasMoreEditApps[tab] ?? false)) {
        setState(() => _tabHasMore[tab] = false);
        return;
      }
      setState(() => _tabIsLoadingMore[tab] = true);
    } else {
      setState(() {
        _tabIsLoading[tab] = true;
        _tabApplications[tab] = [];
        _tabLastNewAppDoc[tab] = null;
        _tabLastEditAppDoc[tab] = null;
        _tabHasMoreNewApps[tab] = true;
        _tabHasMoreEditApps[tab] = true;
        _tabHasMore[tab] = true;
      });
    }

    try {
      final List<VitrinProductApplication> newBatch = [];
      final List<Future<QuerySnapshot>> futures = [];
      final List<String> futureTypes = [];

      // Build query for vitrin_product_applications (only if there might be more)
      if (_tabHasMoreNewApps[tab] ?? false) {
        Query newAppsQuery = _firestore
            .collection('vitrin_product_applications')
            .where('userId', isEqualTo: userId);

        if (tab != VitrinApplicationTab.all) {
          newAppsQuery = newAppsQuery.where('status', isEqualTo: tab.name);
        }

        newAppsQuery = newAppsQuery.orderBy('createdAt', descending: true);

        // Use cursor for pagination
        if (isLoadMore && _tabLastNewAppDoc[tab] != null) {
          newAppsQuery =
              newAppsQuery.startAfterDocument(_tabLastNewAppDoc[tab]!);
        }

        newAppsQuery = newAppsQuery.limit(_pageSize);
        futures.add(newAppsQuery.get());
        futureTypes.add('new');
      }

      // Build query for vitrin_product_edit_applications (only if there might be more)
      if (_tabHasMoreEditApps[tab] ?? false) {
        Query editAppsQuery = _firestore
            .collection('vitrin_product_edit_applications')
            .where('userId', isEqualTo: userId);

        if (tab != VitrinApplicationTab.all) {
          editAppsQuery = editAppsQuery.where('status', isEqualTo: tab.name);
        }

        editAppsQuery = editAppsQuery.orderBy('submittedAt', descending: true);

        // Use cursor for pagination
        if (isLoadMore && _tabLastEditAppDoc[tab] != null) {
          editAppsQuery =
              editAppsQuery.startAfterDocument(_tabLastEditAppDoc[tab]!);
        }

        editAppsQuery = editAppsQuery.limit(_pageSize);
        futures.add(editAppsQuery.get());
        futureTypes.add('edit');
      }

      // No more data to fetch
      if (futures.isEmpty) {
        if (mounted) {
          setState(() {
            _tabHasMore[tab] = false;
            _tabIsLoading[tab] = false;
            _tabIsLoadingMore[tab] = false;
          });
        }
        return;
      }

      final results = await Future.wait(futures);

      // Process results based on their type
      for (int i = 0; i < results.length; i++) {
        final snapshot = results[i];
        final type = futureTypes[i];

        if (type == 'new') {
          for (final doc in snapshot.docs) {
            newBatch
                .add(VitrinProductApplication.fromDocument(doc, isEdit: false));
          }
          // Update cursor and hasMore flag
          if (snapshot.docs.isNotEmpty) {
            _tabLastNewAppDoc[tab] = snapshot.docs.last;
          }
          _tabHasMoreNewApps[tab] = snapshot.docs.length == _pageSize;
        } else if (type == 'edit') {
          for (final doc in snapshot.docs) {
            newBatch
                .add(VitrinProductApplication.fromDocument(doc, isEdit: true));
          }
          // Update cursor and hasMore flag
          if (snapshot.docs.isNotEmpty) {
            _tabLastEditAppDoc[tab] = snapshot.docs.last;
          }
          _tabHasMoreEditApps[tab] = snapshot.docs.length == _pageSize;
        }
      }

      // Sort combined results by submittedAt descending
      newBatch.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      // Update overall hasMore for this tab
      _tabHasMore[tab] =
          (_tabHasMoreNewApps[tab] ?? false) || (_tabHasMoreEditApps[tab] ?? false);

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _tabApplications[tab]!.addAll(newBatch);
          } else {
            _tabApplications[tab] = newBatch;
          }
          _tabIsLoading[tab] = false;
          _tabIsLoadingMore[tab] = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching applications: $e');
      if (mounted) {
        setState(() {
          _tabIsLoading[tab] = false;
          _tabIsLoadingMore[tab] = false;
        });
      }
    }
  }

  Future<void> _loadMoreApplications(VitrinApplicationTab tab) async {
    if (_tabIsLoadingMore[tab] ?? false) return;
    if (!(_tabHasMore[tab] ?? false)) return;
    await _fetchApplications(tab: tab, isLoadMore: true);
  }

  void _showApplicationDetail(VitrinProductApplication application) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VitrinApplicationDetailSheet(
        application: application,
        isDark: isDark,
        l10n: l10n,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    // Check if user is logged in
    if (_currentUserId == null) {
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
        appBar: _buildAppBar(isDark, l10n),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.login_rounded,
                size: 64,
                color: isDark ? Colors.white38 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.pleaseLoginToViewApplications,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1A29) : const Color(0xFFF8FAFC),
      appBar: _buildAppBar(isDark, l10n),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildTabBar(isDark, l10n),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: VitrinApplicationTab.values.map((tab) {
                  return _buildTabContent(tab, isDark, l10n);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build content for each tab with lazy loading support
  Widget _buildTabContent(
      VitrinApplicationTab tab, bool isDark, AppLocalizations l10n) {
    final isLoading = _tabIsLoading[tab] ?? false;
    final applications = _tabApplications[tab] ?? [];
    final hasLoaded = _loadedTabs.contains(tab);

    // If tab hasn't been loaded yet, show loading indicator
    // This triggers lazy loading when the tab is first swiped to
    if (!hasLoaded) {
      // Schedule loading after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTabDataIfNeeded(tab);
      });
      return _buildLoadingSkeleton(isDark);
    }

    if (isLoading) {
      return _buildLoadingSkeleton(isDark);
    }

    if (applications.isEmpty) {
      return _buildEmptyState(tab, isDark, l10n);
    }

    return _buildApplicationsList(tab, isDark, l10n);
  }

  PreferredSizeWidget _buildAppBar(bool isDark, AppLocalizations l10n) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_rounded,
          color: isDark ? Colors.white : Colors.grey[800],
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
        l10n.myProductApplications,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.grey[900],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark, AppLocalizations l10n) {
    // Detect tablet for centering tabs
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

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
        isScrollable: true,
        tabAlignment: isTablet ? TabAlignment.center : TabAlignment.start,
        padding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withOpacity(0.3),
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
        tabs: [
          _buildModernTab(
            l10n.all,
            Icons.apps_rounded,
            _counts[VitrinApplicationTab.all] ?? 0,
          ),
          _buildModernTab(
            l10n.pending,
            Icons.hourglass_empty_rounded,
            _counts[VitrinApplicationTab.pending] ?? 0,
          ),
          _buildModernTab(
            l10n.approved,
            Icons.check_circle_outline_rounded,
            _counts[VitrinApplicationTab.approved] ?? 0,
          ),
          _buildModernTab(
            l10n.rejected,
            Icons.cancel_outlined,
            _counts[VitrinApplicationTab.rejected] ?? 0,
          ),
        ],
      ),
    );
  }

  Widget _buildModernTab(String text, IconData icon, int count) {
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
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    final baseColor = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlightColor =
        isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      VitrinApplicationTab tab, bool isDark, AppLocalizations l10n) {
    String title;
    String description;
    String icon;

    switch (tab) {
      case VitrinApplicationTab.all:
        title = l10n.noApplicationsTitle;
        description = l10n.noVitrinApplicationsDescription;
        icon = '📦';
        break;
      case VitrinApplicationTab.pending:
        title = l10n.noPendingTitle;
        description = l10n.noPendingDescription;
        icon = '⏳';
        break;
      case VitrinApplicationTab.approved:
        title = l10n.noApprovedTitle;
        description = l10n.noApprovedDescription;
        icon = '✓';
        break;
      case VitrinApplicationTab.rejected:
        title = l10n.noRejectedTitle;
        description = l10n.noRejectedDescription;
        icon = '✕';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  icon,
                  style: const TextStyle(fontSize: 40),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.grey[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationsList(
      VitrinApplicationTab tab, bool isDark, AppLocalizations l10n) {
    final applications = _tabApplications[tab] ?? [];
    final isLoadingMore = _tabIsLoadingMore[tab] ?? false;
    final hasMore = _tabHasMore[tab] ?? false;
    final scrollController = _scrollControllers[tab]!;

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchCounts();
        // Reset tab state and reload
        _loadedTabs.remove(tab);
        _loadTabDataIfNeeded(tab);
      },
      color: const Color(0xFF667EEA),
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.of(context).size.width >= 600 ? 3 : 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _VitrinApplicationCard(
                  application: applications[index],
                  isDark: isDark,
                  l10n: l10n,
                  onTap: () => _showApplicationDetail(applications[index]),
                ),
                childCount: applications.length,
              ),
            ),
          ),
          if (isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? Colors.white54 : Colors.grey[400]!,
                    ),
                  ),
                ),
              ),
            ),
          if (hasMore && !isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => _loadMoreApplications(tab),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    label: Text(l10n.loadMore),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: Text(
                  l10n.showingResults(
                    applications.length.toString(),
                    (_counts[tab] ?? 0).toString(),
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status badge widget for vitrin applications
class _VitrinStatusBadge extends StatelessWidget {
  final String status;
  final bool isDark;
  final AppLocalizations l10n;

  const _VitrinStatusBadge({
    required this.status,
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Color borderColor;
    String icon;
    String label;

    switch (status) {
      case 'pending':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        borderColor = const Color(0xFFFDE68A);
        icon = '⏳';
        label = l10n.pending;
        break;
      case 'approved':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        borderColor = const Color(0xFFA7F3D0);
        icon = '✓';
        label = l10n.approved;
        break;
      case 'rejected':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        borderColor = const Color(0xFFFECACA);
        icon = '✕';
        label = l10n.rejected;
        break;
      default:
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        borderColor = const Color(0xFFFDE68A);
        icon = '⏳';
        label = l10n.pending;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Application card widget for vitrin
class _VitrinApplicationCard extends StatelessWidget {
  final VitrinProductApplication application;
  final bool isDark;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const _VitrinApplicationCard({
    required this.application,
    required this.isDark,
    required this.l10n,
    required this.onTap,
  });

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().add_Hm().format(date);
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    ).format(price);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: application.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: application.imageUrls.first,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color:
                                  isDark ? Colors.grey[800] : Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) =>
                                _buildPlaceholder(isDark),
                          )
                        : _buildPlaceholder(isDark),
                  ),

                  // Status badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _VitrinStatusBadge(
                      status: application.status,
                      isDark: isDark,
                      l10n: l10n,
                    ),
                  ),

                  // Edit badge
                  if (application.isEditApplication)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF93C5FD),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_rounded,
                              size: 10,
                              color: Color(0xFF1E40AF),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              l10n.edit,
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E40AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Image count
                  if (application.imageUrls.length > 1)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              application.imageUrls.length.toString(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
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
            ),

            // Content section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title & Price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            application.productName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.grey[800],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatPrice(application.price),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF667EEA),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Category path
                    Text(
                      [
                        application.category,
                        if (application.subcategory.isNotEmpty)
                          application.subcategory,
                        if (application.subsubcategory.isNotEmpty)
                          application.subsubcategory,
                      ].join(' > '),
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const Spacer(),

                    // Rejection reason
                    if (application.status == 'rejected' &&
                        application.rejectionReason != null)
                      Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFECACA),
                          ),
                        ),
                        child: Text(
                          application.rejectionReason!,
                          style: GoogleFonts.inter(
                            fontSize: 8,
                            color: const Color(0xFF991B1B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // Date & View details
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 10,
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            _formatDate(application.submittedAt),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color:
                                  isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10,
                          color: Color(0xFF667EEA),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }
}

/// Application detail bottom sheet for vitrin
class _VitrinApplicationDetailSheet extends StatelessWidget {
  final VitrinProductApplication application;
  final bool isDark;
  final AppLocalizations l10n;

  const _VitrinApplicationDetailSheet({
    required this.application,
    required this.isDark,
    required this.l10n,
  });

  String _formatDate(DateTime date) {
    return DateFormat.yMMMMd().add_Hm().format(date);
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    ).format(price);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1A29) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
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
                _VitrinStatusBadge(
                  status: application.status,
                  isDark: isDark,
                  l10n: l10n,
                ),
                if (application.isEditApplication) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: Color(0xFF1E40AF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.editApplication,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Images
                  if (application.imageUrls.isNotEmpty) ...[
                    Text(
                      l10n.images,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: application.imageUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: application.imageUrls[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Product name & price
                  Text(
                    application.productName,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatPrice(application.price),
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF667EEA),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description
                  if (application.description.isNotEmpty) ...[
                    Text(
                      l10n.description,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      application.description,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Details grid
                  _buildDetailGrid(),

                  // Colors
                  if (application.availableColors != null &&
                      application.availableColors!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.colors,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: application.availableColors!.map((color) {
                        final qty = application.colorQuantities?[color];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey[300]!,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                color,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[700],
                                ),
                              ),
                              if (qty != null) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '($qty)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // Edited fields
                  if (application.isEditApplication &&
                      application.editedFields != null &&
                      application.editedFields!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF93C5FD)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.editedFields,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: application.editedFields!.map((field) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFBFDBFE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  field,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF1E40AF),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Rejection reason
                  if (application.status == 'rejected' &&
                      application.rejectionReason != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.rejectionReason,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            application.rejectionReason!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Timestamps
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.2),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              '${l10n.submittedAt}: ',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[500],
                              ),
                            ),
                            Text(
                              _formatDate(application.submittedAt),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        if (application.reviewedAt != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${l10n.reviewedAt}: ',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[500]
                                      : Colors.grey[500],
                                ),
                              ),
                              Text(
                                _formatDate(application.reviewedAt!),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Close button with SafeArea for bottom navigation
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100],
                    foregroundColor: isDark ? Colors.white : Colors.grey[800],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.close,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDetailItem(
                l10n.category,
                [
                  application.category,
                  if (application.subcategory.isNotEmpty)
                    application.subcategory,
                  if (application.subsubcategory.isNotEmpty)
                    application.subsubcategory,
                ].join(' > '),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDetailItem(
                l10n.condition,
                application.condition,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDetailItem(
                l10n.quantity,
                application.quantity.toString(),
              ),
            ),
          ],
        ),
        if (application.brandModel != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  l10n.brand,
                  application.brandModel!,
                ),
              ),
            ],
          ),
        ],
        if (application.gender != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailItem(
                  l10n.gender,
                  application.gender!,
                ),
              ),
              if (application.deliveryOption != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailItem(
                    l10n.delivery,
                    application.deliveryOption!,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[500] : Colors.grey[500],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ],
    );
  }
}
