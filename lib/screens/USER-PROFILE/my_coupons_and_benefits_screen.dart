// lib/screens/USER-PROFILE/my_coupons_and_benefits_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/coupon.dart';
import '../../models/user_benefit.dart';
import '../../widgets/coupon_widget.dart';

class MyCouponsAndBenefitsScreen extends StatefulWidget {
  const MyCouponsAndBenefitsScreen({super.key});

  @override
  State<MyCouponsAndBenefitsScreen> createState() =>
      _MyCouponsAndBenefitsScreenState();
}

class _MyCouponsAndBenefitsScreenState
    extends State<MyCouponsAndBenefitsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  // Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Pagination constants
  static const int _pageSize = 20;

  // Active coupons state
  final List<Coupon> _activeCoupons = [];
  DocumentSnapshot? _lastActiveCouponDoc;
  bool _hasMoreActiveCoupons = true;
  bool _isLoadingActiveCoupons = false;
  bool _initialActiveCouponsLoaded = false;

  // Used coupons state
  final List<Coupon> _usedCoupons = [];
  DocumentSnapshot? _lastUsedCouponDoc;
  bool _hasMoreUsedCoupons = true;
  bool _isLoadingUsedCoupons = false;
  bool _initialUsedCouponsLoaded = false;

  // Active benefits state
  final List<UserBenefit> _activeBenefits = [];
  DocumentSnapshot? _lastActiveBenefitDoc;
  bool _hasMoreActiveBenefits = true;
  bool _isLoadingActiveBenefits = false;

  // Used benefits state
  final List<UserBenefit> _usedBenefits = [];
  DocumentSnapshot? _lastUsedBenefitDoc;
  bool _hasMoreUsedBenefits = true;
  bool _isLoadingUsedBenefits = false;

  // Scroll controllers for pagination
  final ScrollController _activeScrollController = ScrollController();
  final ScrollController _usedScrollController = ScrollController();

  // Error states
  String? _activeError;
  String? _usedError;

  // Prevent concurrent fetches
  final Set<String> _pendingFetches = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    _activeScrollController.addListener(_onActiveScroll);
    _usedScrollController.addListener(_onUsedScroll);

    // Load initial data
    _loadInitialActiveCouponsAndBenefits();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _activeScrollController.dispose();
    _usedScrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_initialUsedCouponsLoaded) {
      _loadInitialUsedCouponsAndBenefits();
    }
  }

  void _onActiveScroll() {
    if (_activeScrollController.position.pixels >=
        _activeScrollController.position.maxScrollExtent - 200) {
      _loadMoreActiveCoupons();
      _loadMoreActiveBenefits();
    }
  }

  void _onUsedScroll() {
    if (_usedScrollController.position.pixels >=
        _usedScrollController.position.maxScrollExtent - 200) {
      _loadMoreUsedCoupons();
      _loadMoreUsedBenefits();
    }
  }

  String? get _userId => _auth.currentUser?.uid;

  // ════════════════════════════════════════════════════════════════════════════
  // ACTIVE COUPONS & BENEFITS LOADING
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _loadInitialActiveCouponsAndBenefits() async {
    if (_userId == null) return;

    setState(() {
      _isLoadingActiveCoupons = true;
      _isLoadingActiveBenefits = true;
      _activeError = null;
    });

    await Future.wait([
      _fetchActiveCoupons(isInitial: true),
      _fetchActiveBenefits(isInitial: true),
    ]);

    if (mounted) {
      setState(() {
        _initialActiveCouponsLoaded = true;
      });
    }
  }

  Future<void> _fetchActiveCoupons({bool isInitial = false}) async {
    if (_pendingFetches.contains('activeCoupons')) return;
    if (!_hasMoreActiveCoupons && !isInitial) return;

    _pendingFetches.add('activeCoupons');

    try {
      Query query = _firestore
          .collection('users')
          .doc(_userId)
          .collection('coupons')
          .where('isUsed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastActiveCouponDoc != null) {
        query = query.startAfterDocument(_lastActiveCouponDoc!);
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      if (!mounted) return;

      final newCoupons = snapshot.docs
          .map((doc) => Coupon.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      setState(() {
        if (isInitial) {
          _activeCoupons.clear();
        }

        // Deduplicate
        final existingIds = _activeCoupons.map((c) => c.id).toSet();
        for (final coupon in newCoupons) {
          if (!existingIds.contains(coupon.id)) {
            _activeCoupons.add(coupon);
          }
        }

        if (snapshot.docs.isNotEmpty) {
          _lastActiveCouponDoc = snapshot.docs.last;
        }
        _hasMoreActiveCoupons = snapshot.docs.length >= _pageSize;
        _isLoadingActiveCoupons = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeError = e.toString();
          _isLoadingActiveCoupons = false;
        });
      }
      debugPrint('Error fetching active coupons: $e');
    } finally {
      _pendingFetches.remove('activeCoupons');
    }
  }

  Future<void> _fetchActiveBenefits({bool isInitial = false}) async {
    if (_pendingFetches.contains('activeBenefits')) return;
    if (!_hasMoreActiveBenefits && !isInitial) return;

    _pendingFetches.add('activeBenefits');

    try {
      Query query = _firestore
          .collection('users')
          .doc(_userId)
          .collection('benefits')
          .where('isUsed', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastActiveBenefitDoc != null) {
        query = query.startAfterDocument(_lastActiveBenefitDoc!);
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      if (!mounted) return;

      final newBenefits = snapshot.docs
          .map((doc) =>
              UserBenefit.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      setState(() {
        if (isInitial) {
          _activeBenefits.clear();
        }

        // Deduplicate
        final existingIds = _activeBenefits.map((b) => b.id).toSet();
        for (final benefit in newBenefits) {
          if (!existingIds.contains(benefit.id)) {
            _activeBenefits.add(benefit);
          }
        }

        if (snapshot.docs.isNotEmpty) {
          _lastActiveBenefitDoc = snapshot.docs.last;
        }
        _hasMoreActiveBenefits = snapshot.docs.length >= _pageSize;
        _isLoadingActiveBenefits = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeError = e.toString();
          _isLoadingActiveBenefits = false;
        });
      }
      debugPrint('Error fetching active benefits: $e');
    } finally {
      _pendingFetches.remove('activeBenefits');
    }
  }

  Future<void> _loadMoreActiveCoupons() async {
    if (_isLoadingActiveCoupons || !_hasMoreActiveCoupons) return;
    setState(() => _isLoadingActiveCoupons = true);
    await _fetchActiveCoupons();
  }

  Future<void> _loadMoreActiveBenefits() async {
    if (_isLoadingActiveBenefits || !_hasMoreActiveBenefits) return;
    setState(() => _isLoadingActiveBenefits = true);
    await _fetchActiveBenefits();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // USED COUPONS & BENEFITS LOADING
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _loadInitialUsedCouponsAndBenefits() async {
    if (_userId == null) return;

    setState(() {
      _isLoadingUsedCoupons = true;
      _isLoadingUsedBenefits = true;
      _usedError = null;
    });

    await Future.wait([
      _fetchUsedCoupons(isInitial: true),
      _fetchUsedBenefits(isInitial: true),
    ]);

    if (mounted) {
      setState(() {
        _initialUsedCouponsLoaded = true;
      });
    }
  }

  Future<void> _fetchUsedCoupons({bool isInitial = false}) async {
    if (_pendingFetches.contains('usedCoupons')) return;
    if (!_hasMoreUsedCoupons && !isInitial) return;

    _pendingFetches.add('usedCoupons');

    try {
      Query query = _firestore
          .collection('users')
          .doc(_userId)
          .collection('coupons')
          .where('isUsed', isEqualTo: true)
          .orderBy('usedAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastUsedCouponDoc != null) {
        query = query.startAfterDocument(_lastUsedCouponDoc!);
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      if (!mounted) return;

      final newCoupons = snapshot.docs
          .map((doc) => Coupon.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      setState(() {
        if (isInitial) {
          _usedCoupons.clear();
        }

        // Deduplicate
        final existingIds = _usedCoupons.map((c) => c.id).toSet();
        for (final coupon in newCoupons) {
          if (!existingIds.contains(coupon.id)) {
            _usedCoupons.add(coupon);
          }
        }

        if (snapshot.docs.isNotEmpty) {
          _lastUsedCouponDoc = snapshot.docs.last;
        }
        _hasMoreUsedCoupons = snapshot.docs.length >= _pageSize;
        _isLoadingUsedCoupons = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _usedError = e.toString();
          _isLoadingUsedCoupons = false;
        });
      }
      debugPrint('Error fetching used coupons: $e');
    } finally {
      _pendingFetches.remove('usedCoupons');
    }
  }

  Future<void> _fetchUsedBenefits({bool isInitial = false}) async {
    if (_pendingFetches.contains('usedBenefits')) return;
    if (!_hasMoreUsedBenefits && !isInitial) return;

    _pendingFetches.add('usedBenefits');

    try {
      Query query = _firestore
          .collection('users')
          .doc(_userId)
          .collection('benefits')
          .where('isUsed', isEqualTo: true)
          .orderBy('usedAt', descending: true)
          .limit(_pageSize);

      if (!isInitial && _lastUsedBenefitDoc != null) {
        query = query.startAfterDocument(_lastUsedBenefitDoc!);
      }

      final snapshot = await query.get(const GetOptions(source: Source.server));

      if (!mounted) return;

      final newBenefits = snapshot.docs
          .map((doc) =>
              UserBenefit.fromJson(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      setState(() {
        if (isInitial) {
          _usedBenefits.clear();
        }

        // Deduplicate
        final existingIds = _usedBenefits.map((b) => b.id).toSet();
        for (final benefit in newBenefits) {
          if (!existingIds.contains(benefit.id)) {
            _usedBenefits.add(benefit);
          }
        }

        if (snapshot.docs.isNotEmpty) {
          _lastUsedBenefitDoc = snapshot.docs.last;
        }
        _hasMoreUsedBenefits = snapshot.docs.length >= _pageSize;
        _isLoadingUsedBenefits = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _usedError = e.toString();
          _isLoadingUsedBenefits = false;
        });
      }
      debugPrint('Error fetching used benefits: $e');
    } finally {
      _pendingFetches.remove('usedBenefits');
    }
  }

  Future<void> _loadMoreUsedCoupons() async {
    if (_isLoadingUsedCoupons || !_hasMoreUsedCoupons) return;
    setState(() => _isLoadingUsedCoupons = true);
    await _fetchUsedCoupons();
  }

  Future<void> _loadMoreUsedBenefits() async {
    if (_isLoadingUsedBenefits || !_hasMoreUsedBenefits) return;
    setState(() => _isLoadingUsedBenefits = true);
    await _fetchUsedBenefits();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // REFRESH
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _refreshActive() async {
    _lastActiveCouponDoc = null;
    _lastActiveBenefitDoc = null;
    _hasMoreActiveCoupons = true;
    _hasMoreActiveBenefits = true;
    await _loadInitialActiveCouponsAndBenefits();
  }

  Future<void> _refreshUsed() async {
    _lastUsedCouponDoc = null;
    _lastUsedBenefitDoc = null;
    _hasMoreUsedCoupons = true;
    _hasMoreUsedBenefits = true;
    await _loadInitialUsedCouponsAndBenefits();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            FeatherIcons.arrowLeft,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.myCouponsAndBenefits,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _buildTabBar(isDark, l10n),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveTab(isDark, l10n),
          _buildUsedTab(isDark, l10n),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark, AppLocalizations l10n) {
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
          _buildModernTab(l10n.activeCoupons, FeatherIcons.gift),
          _buildModernTab(l10n.usedCoupons, FeatherIcons.checkCircle),
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

  // ════════════════════════════════════════════════════════════════════════════
  // ACTIVE TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildActiveTab(bool isDark, AppLocalizations l10n) {
    final isLoading = _isLoadingActiveCoupons || _isLoadingActiveBenefits;
    final hasError = _activeError != null;
    final isEmpty = _activeCoupons.isEmpty && _activeBenefits.isEmpty;
    final isInitialLoad = !_initialActiveCouponsLoaded;

    if (isInitialLoad && isLoading) {
      return _buildShimmerList(isDark);
    }

    if (hasError && isEmpty) {
      return _buildErrorWidget(isDark, l10n, _activeError!, _refreshActive);
    }

    if (isEmpty && !isLoading) {
      return _buildEmptyState(
        isDark,
        l10n,
        l10n.noCouponsOrBenefits,
        l10n.noCouponsOrBenefitsDescription,
        FeatherIcons.gift,
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshActive,
      color: Colors.orange,
      child: ListView.builder(
        controller: _activeScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _activeBenefits.length +
            _activeCoupons.length +
            (_isLoadingActiveCoupons || _isLoadingActiveBenefits ? 1 : 0),
        itemBuilder: (context, index) {
          // Benefits first
          if (index < _activeBenefits.length) {
            return _buildBenefitCard(_activeBenefits[index], isDark, l10n, false);
          }

          // Then coupons
          final couponIndex = index - _activeBenefits.length;
          if (couponIndex < _activeCoupons.length) {
            return _buildCouponCard(_activeCoupons[couponIndex], isDark, l10n, false);
          }

          // Loading indicator
          return _buildLoadingIndicator(isDark);
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // USED TAB
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildUsedTab(bool isDark, AppLocalizations l10n) {
    final isLoading = _isLoadingUsedCoupons || _isLoadingUsedBenefits;
    final hasError = _usedError != null;
    final isEmpty = _usedCoupons.isEmpty && _usedBenefits.isEmpty;
    final isInitialLoad = !_initialUsedCouponsLoaded;

    if (isInitialLoad && isLoading) {
      return _buildShimmerList(isDark);
    }

    if (hasError && isEmpty) {
      return _buildErrorWidget(isDark, l10n, _usedError!, _refreshUsed);
    }

    if (isEmpty && !isLoading) {
      return _buildEmptyState(
        isDark,
        l10n,
        l10n.noUsedCouponsOrBenefits,
        l10n.noUsedCouponsOrBenefitsDescription,
        FeatherIcons.clock,
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshUsed,
      color: Colors.orange,
      child: ListView.builder(
        controller: _usedScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _usedBenefits.length +
            _usedCoupons.length +
            (_isLoadingUsedCoupons || _isLoadingUsedBenefits ? 1 : 0),
        itemBuilder: (context, index) {
          // Benefits first
          if (index < _usedBenefits.length) {
            return _buildBenefitCard(_usedBenefits[index], isDark, l10n, true);
          }

          // Then coupons
          final couponIndex = index - _usedBenefits.length;
          if (couponIndex < _usedCoupons.length) {
            return _buildCouponCard(_usedCoupons[couponIndex], isDark, l10n, true);
          }

          // Loading indicator
          return _buildLoadingIndicator(isDark);
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // CARD WIDGETS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildCouponCard(
      Coupon coupon, bool isDark, AppLocalizations l10n, bool isUsed) {
    final locale = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat('dd MMM yyyy', locale);
    final expiryText = coupon.expiresAt != null
        ? '${l10n.validUntil} ${dateFormat.format(coupon.expiresAt!.toDate())}'
        : l10n.noExpiry;

    final usedText = coupon.usedAt != null
        ? '${l10n.usedOn} ${dateFormat.format(coupon.usedAt!.toDate())}'
        : '';

    // Determine status color and text
    Color statusColor;
    String statusText;
    if (isUsed) {
      statusColor = Colors.grey;
      statusText = l10n.used;
    } else if (coupon.status == CouponStatus.expired) {
      statusColor = Colors.red;
      statusText = l10n.expired;
    } else {
      statusColor = Colors.green;
      statusText = l10n.active;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coupon visual widget
          Opacity(
            opacity: isUsed ? 0.6 : 1.0,
            child: Center(
              child: CouponWidget(
                leftText: l10n.enjoyYourGift,
                discount: '${coupon.amount.toStringAsFixed(0)} ${coupon.currency}',
                subtitle: l10n.coupon,
                validUntil: isUsed ? usedText : expiryText,
                code: coupon.code ?? coupon.id.substring(0, 8).toUpperCase(),
                primaryColor: isUsed
                    ? Colors.grey
                    : const Color(0xFFFFD700), // Gold for active
                width: MediaQuery.of(context).size.width - 32,
                height: 140,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Status badge and description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (coupon.description != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.description!,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitCard(
      UserBenefit benefit, bool isDark, AppLocalizations l10n, bool isUsed) {
    final locale = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat('dd MMM yyyy', locale);
    final expiryText = benefit.expiresAt != null
        ? '${l10n.validUntil} ${dateFormat.format(benefit.expiresAt!.toDate())}'
        : l10n.noExpiry;

    final usedText = benefit.usedAt != null
        ? '${l10n.usedOn} ${dateFormat.format(benefit.usedAt!.toDate())}'
        : '';

    // Determine status color and text
    Color statusColor;
    String statusText;
    if (isUsed) {
      statusColor = Colors.grey;
      statusText = l10n.used;
    } else if (benefit.status == BenefitStatus.expired) {
      statusColor = Colors.red;
      statusText = l10n.expired;
    } else {
      statusColor = Colors.green;
      statusText = l10n.active;
    }

    // Get benefit type display
    String benefitTitle;
    String benefitDescription;
    IconData benefitIcon;
    Color benefitColor;

    switch (benefit.type) {
      case BenefitType.freeShipping:
        benefitTitle = l10n.freeShipping;
        benefitDescription = l10n.freeShippingBenefitDescription;
        benefitIcon = FeatherIcons.truck;
        benefitColor = isUsed ? Colors.grey : Colors.blue;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2B3F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUsed
              ? Colors.grey.withValues(alpha: 0.3)
              : benefitColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: isUsed ? 0.7 : 1.0,
        child: Row(
          children: [
            // Icon container
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: benefitColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                benefitIcon,
                color: benefitColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          benefitTitle,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    benefitDescription,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isUsed ? usedText : expiryText,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildLoadingIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: isDark ? Colors.white54 : Colors.black38,
        ),
      ),
    );
  }

  Widget _buildShimmerList(bool isDark) {
    final baseColor =
        isDark ? const Color.fromARGB(255, 30, 28, 44) : Colors.grey[300]!;
    final highlightColor =
        isDark ? const Color.fromARGB(255, 45, 42, 65) : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    bool isDark,
    AppLocalizations l10n,
    String title,
    String description,
    IconData icon,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: isDark ? Colors.white38 : Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(
    bool isDark,
    AppLocalizations l10n,
    String error,
    VoidCallback onRetry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FeatherIcons.alertCircle,
                size: 48,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.couponsErrorLoadingData,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.couponsTryAgainLater,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(FeatherIcons.refreshCw, size: 18),
              label: Text(l10n.retry),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
