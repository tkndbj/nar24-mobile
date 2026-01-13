import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Modern color palette
const Color primaryAccent = Color(0xFF6366F1); // Indigo
const Color successColor = Color(0xFF10B981); // Emerald
const Color warningColor = Color(0xFFF59E0B); // Amber
const Color errorColor = Color(0xFFEF4444); // Red
const Color neutralColor = Color(0xFF6B7280); // Gray
const Color maleColor = Color(0xFF3B82F6); // Blue
const Color femaleColor = Color(0xFFEC4899); // Pink
const Color otherColor = Color(0xFF8B5CF6); // Purple
const int pageSize = 10;

class SellerPanelAdsAnalytics extends StatefulWidget {
  final String shopId;

  const SellerPanelAdsAnalytics({
    Key? key,
    required this.shopId,
  }) : super(key: key);

  @override
  _SellerPanelAdsAnalyticsState createState() =>
      _SellerPanelAdsAnalyticsState();
}

class _SellerPanelAdsAnalyticsState extends State<SellerPanelAdsAnalytics> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DateFormat _dateFormat = DateFormat('MMM d, y');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  DocumentSnapshot? _lastDocument;
  List<DocumentSnapshot> _boostHistoryDocs = [];
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      final querySnapshot = await _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('boostHistory')
          .orderBy('boostStartTime', descending: true)
          .limit(pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _boostHistoryDocs = querySnapshot.docs;
        _lastDocument =
            querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;
        _hasMoreData = querySnapshot.docs.length == pageSize;
        _isInitialLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitialLoad = false);
      _showErrorSnackbar('Failed to load data');
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() => _isLoadingMore = true);

    try {
      final querySnapshot = await _firestore
          .collection('shops')
          .doc(widget.shopId)
          .collection('boostHistory')
          .orderBy('boostStartTime', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _boostHistoryDocs.addAll(querySnapshot.docs);
        _lastDocument =
            querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;
        _hasMoreData = querySnapshot.docs.length == pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      _showErrorSnackbar('Failed to load more data');
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreData();
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          l10n.boostAnalytics,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.grey[900],
            fontWeight: FontWeight.w600,
            fontSize: 20,
            fontFamily: 'Figtree',
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.grey[900],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _isInitialLoad
            ? _buildShimmerLoading(isDark)
            : _boostHistoryDocs.isEmpty
                ? _buildEmptyState(l10n, isDark)
                : RefreshIndicator(
                    onRefresh: _loadInitialData,
                    color: primaryAccent,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount:
                          _boostHistoryDocs.length + (_hasMoreData ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _boostHistoryDocs.length) {
                          return _buildLoadMoreShimmer(isDark);
                        }

                        final doc = _boostHistoryDocs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final itemId = data['itemId']?.toString() ?? '';

                      return _ModernBoostAnalyticsCard(
                        boostDoc: data,
                        itemId: itemId,
                        isDark: isDark,
                      );
                    },
                  ),
                ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: primaryAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bar_chart_rounded,
              size: 48,
              color: primaryAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noBoostHistory,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              fontFamily: 'Figtree',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start boosting your products to see analytics here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontFamily: 'Figtree',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    final baseColor =
        isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D4A) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 4,
        itemBuilder: (context, index) => _buildAnalyticsCardShimmer(isDark),
      ),
    );
  }

  Widget _buildLoadMoreShimmer(bool isDark) {
    final baseColor =
        isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D4A) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _buildAnalyticsCardShimmer(isDark),
      ),
    );
  }

  Widget _buildAnalyticsCardShimmer(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B23) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Product Image placeholder
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2D2D3A)
                        : const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                // Product Info placeholder
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShimmerBox(width: 150, height: 18, isDark: isDark),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildShimmerBox(
                              width: 70, height: 24, isDark: isDark),
                          const SizedBox(width: 8),
                          _buildShimmerBox(
                              width: 50, height: 16, isDark: isDark),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Metrics Row placeholder
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: _buildMetricShimmer(isDark)),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricShimmer(isDark)),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricShimmer(isDark)),
              ],
            ),
          ),
          // Duration Info placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                _buildShimmerBox(width: 80, height: 14, isDark: isDark),
                const Spacer(),
                _buildShimmerBox(width: 100, height: 14, isDark: isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricShimmer(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3D3D4A) : const Color(0xFFD0D0D0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 18,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3D3D4A) : const Color(0xFFD0D0D0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 50,
            height: 12,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3D3D4A) : const Color(0xFFD0D0D0),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required bool isDark,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D3A) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ModernBoostAnalyticsCard extends StatefulWidget {
  final Map<String, dynamic> boostDoc;
  final String itemId;
  final bool isDark;

  const _ModernBoostAnalyticsCard({
    Key? key,
    required this.boostDoc,
    required this.itemId,
    required this.isDark,
  }) : super(key: key);

  @override
  State<_ModernBoostAnalyticsCard> createState() =>
      _ModernBoostAnalyticsCardState();
}

class _ModernBoostAnalyticsCardState extends State<_ModernBoostAnalyticsCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Extract denormalized data from boost history
    final String itemName = widget.boostDoc['itemName'] ?? 'Unnamed Product';
    final String? productImage = widget.boostDoc['productImage'];
    final double averageRating =
        (widget.boostDoc['averageRating'] ?? 0).toDouble();
    final num price = widget.boostDoc['price'] ?? 0;
    final String currency = widget.boostDoc['currency'] ?? 'TL';

    // Boost metrics
    final impressionsDuringBoost =
        widget.boostDoc['impressionsDuringBoost']?.toInt() ?? 0;
    final clicksDuringBoost =
        widget.boostDoc['clicksDuringBoost']?.toInt() ?? 0;
    final ctr = (impressionsDuringBoost > 0)
        ? ((clicksDuringBoost / impressionsDuringBoost) * 100)
        : 0.0;

    // Demographics data
    final demographics =
        widget.boostDoc['demographics'] as Map<String, dynamic>?;
    final viewerAgeGroups =
        widget.boostDoc['viewerAgeGroups'] as Map<String, dynamic>?;

    final hasDemographics = (demographics != null && demographics.isNotEmpty) ||
        (viewerAgeGroups != null && viewerAgeGroups.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color.fromARGB(255, 37, 35, 54)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
                (widget.isDark ? Colors.black : Colors.grey).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Product Image
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[300],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: productImage != null
                          ? CachedNetworkImage(
                              imageUrl: productImage,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child:
                                    Icon(Icons.image, color: Colors.grey[500]),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: Icon(Icons.broken_image,
                                    color: Colors.grey[500]),
                              ),
                            )
                          : Container(
                              color: Colors.grey[300],
                              child: Icon(Icons.image, color: Colors.grey[500]),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Product Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color:
                                widget.isDark ? Colors.white : Colors.grey[900],
                            fontFamily: 'Figtree',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Price and Rating Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$price $currency',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryAccent,
                                  fontFamily: 'Figtree',
                                ),
                              ),
                            ),
                            if (averageRating > 0) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Colors.amber[600],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                averageRating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber[600],
                                  fontFamily: 'Figtree',
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

            // Analytics Grid
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      Icons.visibility_rounded,
                      primaryAccent,
                      impressionsDuringBoost.toString(),
                      l10n.impressions,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      Icons.touch_app_rounded,
                      successColor,
                      clicksDuringBoost.toString(),
                      l10n.clicks,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      Icons.trending_up_rounded,
                      warningColor,
                      '${ctr.toStringAsFixed(1)}%',
                      'CTR',
                    ),
                  ),
                ],
              ),
            ),

            // Demographics Section (Expandable)
            if (hasDemographics)
              Column(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_rounded,
                            size: 18,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getLocalizedDemographics(l10n),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                              fontFamily: 'Figtree',
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: widget.isDark
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gender Demographics
                          if (demographics != null &&
                              demographics.isNotEmpty) ...[
                            _buildSectionHeader(
                                l10n, _getLocalizedGender(l10n)),
                            const SizedBox(height: 8),
                            _buildGenderChart(demographics, l10n),
                            const SizedBox(height: 16),
                          ],

                          // Age Demographics
                          if (viewerAgeGroups != null &&
                              viewerAgeGroups.isNotEmpty) ...[
                            _buildSectionHeader(l10n, _getLocalizedAge(l10n)),
                            const SizedBox(height: 8),
                            _buildAgeChart(viewerAgeGroups, l10n),
                          ],
                        ],
                      ),
                    ),
                ],
              ),

            // Duration Info
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.boostDoc['boostDuration']} ${_getLocalizedMinutes(l10n)}',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          widget.isDark ? Colors.grey[400] : Colors.grey[600],
                      fontFamily: 'Figtree',
                    ),
                  ),
                  const Spacer(),
                  if (widget.boostDoc['boostEndTime'] != null)
                    Text(
                      DateFormat('MMM d, y').format(
                          (widget.boostDoc['boostEndTime'] as Timestamp)
                              .toDate()),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            widget.isDark ? Colors.grey[400] : Colors.grey[600],
                        fontFamily: 'Figtree',
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

  Widget _buildSectionHeader(AppLocalizations l10n, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
        fontFamily: 'Figtree',
      ),
    );
  }

  Widget _buildGenderChart(
      Map<String, dynamic> demographics, AppLocalizations l10n) {
    final total =
        demographics.values.fold<int>(0, (sum, val) => sum + (val as int));

    if (total == 0) {
      return Text(
        _getLocalizedNoData(l10n),
        style: TextStyle(
          fontSize: 11,
          color: widget.isDark ? Colors.grey[500] : Colors.grey[500],
          fontFamily: 'Figtree',
        ),
      );
    }

    return Column(
      children: demographics.entries.map((entry) {
        final gender = entry.key;
        final count = entry.value as int;
        final percentage = (count / total * 100);

        Color genderColor;
        IconData genderIcon;
        String genderLabel;

        switch (gender.toLowerCase()) {
          case 'male':
            genderColor = maleColor;
            genderIcon = Icons.male_rounded;
            genderLabel = _getLocalizedMale(l10n);
            break;
          case 'female':
            genderColor = femaleColor;
            genderIcon = Icons.female_rounded;
            genderLabel = _getLocalizedFemale(l10n);
            break;
          default:
            genderColor = otherColor;
            genderIcon = Icons.person_rounded;
            genderLabel = _getLocalizedOther(l10n);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(genderIcon, size: 16, color: genderColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          genderLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.grey[300]
                                : Colors.grey[700],
                            fontFamily: 'Figtree',
                          ),
                        ),
                        Text(
                          '$count (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: genderColor,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor:
                            widget.isDark ? Colors.grey[700] : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(genderColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAgeChart(Map<String, dynamic> ageGroups, AppLocalizations l10n) {
    final total =
        ageGroups.values.fold<int>(0, (sum, val) => sum + (val as int));

    if (total == 0) {
      return Text(
        _getLocalizedNoData(l10n),
        style: TextStyle(
          fontSize: 11,
          color: widget.isDark ? Colors.grey[500] : Colors.grey[500],
          fontFamily: 'Figtree',
        ),
      );
    }

    // Sort age groups in logical order
    final sortedEntries = ageGroups.entries.toList()
      ..sort((a, b) {
        final order = {
          'under18': 0,
          '18-24': 1,
          '25-34': 2,
          '35-44': 3,
          '45-54': 4,
          '55plus': 5,
          'unknown': 6,
        };
        return (order[a.key] ?? 999).compareTo(order[b.key] ?? 999);
      });

    return Column(
      children: sortedEntries.map((entry) {
        final ageGroup = entry.key;
        final count = entry.value as int;
        final percentage = (count / total * 100);

        final ageLabel = _getLocalizedAgeGroup(ageGroup, l10n);
        final ageColor = _getAgeGroupColor(ageGroup);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ageColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ageLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.grey[300]
                                : Colors.grey[700],
                            fontFamily: 'Figtree',
                          ),
                        ),
                        Text(
                          '$count (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ageColor,
                            fontFamily: 'Figtree',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor:
                            widget.isDark ? Colors.grey[700] : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(ageColor),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getAgeGroupColor(String ageGroup) {
    switch (ageGroup) {
      case 'under18':
        return const Color(0xFFEC4899); // Pink
      case '18-24':
        return const Color(0xFF8B5CF6); // Purple
      case '25-34':
        return const Color(0xFF3B82F6); // Blue
      case '35-44':
        return const Color(0xFF10B981); // Emerald
      case '45-54':
        return const Color(0xFFF59E0B); // Amber
      case '55plus':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  String _getLocalizedAgeGroup(String ageGroup, AppLocalizations l10n) {
    // You'll need to add these to your l10n files
    switch (ageGroup) {
      case 'under18':
        return l10n.localeName == 'tr'
            ? '18 yaş altı'
            : l10n.localeName == 'ru'
                ? 'Младше 18'
                : 'Under 18';
      case '18-24':
        return '18-24';
      case '25-34':
        return '25-34';
      case '35-44':
        return '35-44';
      case '45-54':
        return '45-54';
      case '55plus':
        return l10n.localeName == 'tr'
            ? '55+'
            : l10n.localeName == 'ru'
                ? '55+'
                : '55+';
      default:
        return l10n.localeName == 'tr'
            ? 'Bilinmiyor'
            : l10n.localeName == 'ru'
                ? 'Неизвестно'
                : 'Unknown';
    }
  }

  String _getLocalizedDemographics(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Demografik Veriler'
        : l10n.localeName == 'ru'
            ? 'Демографические данные'
            : 'Demographics';
  }

  String _getLocalizedGender(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Cinsiyet'
        : l10n.localeName == 'ru'
            ? 'Пол'
            : 'Gender';
  }

  String _getLocalizedAge(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Yaş Grupları'
        : l10n.localeName == 'ru'
            ? 'Возрастные группы'
            : 'Age Groups';
  }

  String _getLocalizedMale(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Erkek'
        : l10n.localeName == 'ru'
            ? 'Мужской'
            : 'Male';
  }

  String _getLocalizedFemale(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Kadın'
        : l10n.localeName == 'ru'
            ? 'Женский'
            : 'Female';
  }

  String _getLocalizedOther(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Diğer'
        : l10n.localeName == 'ru'
            ? 'Другое'
            : 'Other';
  }

  String _getLocalizedMinutes(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'dakika'
        : l10n.localeName == 'ru'
            ? 'минут'
            : 'minutes';
  }

  String _getLocalizedNoData(AppLocalizations l10n) {
    return l10n.localeName == 'tr'
        ? 'Veri yok'
        : l10n.localeName == 'ru'
            ? 'Нет данных'
            : 'No data';
  }

  Widget _buildMetricCard(
      IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Figtree',
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
              fontFamily: 'Figtree',
            ),
          ),
        ],
      ),
    );
  }
}
