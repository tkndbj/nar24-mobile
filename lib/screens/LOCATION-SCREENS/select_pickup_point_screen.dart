import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../models/pickup_point.dart';
import '../../../widgets/pickup-point/pickup_point_card.dart';
import '../../../widgets/pickup-point/pickup_point_detail_modal.dart';

class SelectPickupPointScreen extends StatefulWidget {
  const SelectPickupPointScreen({Key? key}) : super(key: key);

  @override
  State<SelectPickupPointScreen> createState() =>
      _SelectPickupPointScreenState();
}

class _SelectPickupPointScreenState extends State<SelectPickupPointScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<PickupPoint> _allPickupPoints = [];
  List<PickupPoint> _filteredPickupPoints = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPickupPoints();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterPickupPoints();
    });
  }

  void _filterPickupPoints() {
    if (_searchQuery.isEmpty) {
      _filteredPickupPoints = List.from(_allPickupPoints);
    } else {
      _filteredPickupPoints = _allPickupPoints.where((point) {
        return point.name.toLowerCase().contains(_searchQuery) ||
            point.address.toLowerCase().contains(_searchQuery) ||
            point.contactPerson.toLowerCase().contains(_searchQuery);
      }).toList();
    }
  }

  Future<void> _loadPickupPoints() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('pickup_points')
          .where('isActive', isEqualTo: true)
          .get();

      // Sort in memory instead of using orderBy to avoid index requirement
      final points = querySnapshot.docs
          .map((doc) => PickupPoint.fromFirestore(doc))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _allPickupPoints = points;
          _filteredPickupPoints = List.from(points);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to load pickup points: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onPickupPointTapped(PickupPoint pickupPoint) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PickupPointDetailModal(pickupPoint: pickupPoint),
    );

    if (result == true && mounted) {
      Navigator.pop(context, pickupPoint);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.selectPickupPoint,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? const Color(0xFF1C1A29) : Colors.white,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2839) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchPickupPoints,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),

          // Content Section
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPickupPoints.isEmpty
                    ? _buildEmptyState(l10n, isDark)
                    : _buildPickupPointsList(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? l10n.noPickupPointsFound
                : l10n.noPickupPointsAvailable,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.tryDifferentSearch,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupPointsList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadPickupPoints,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredPickupPoints.length,
        itemBuilder: (context, index) {
          final pickupPoint = _filteredPickupPoints[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PickupPointCard(
              pickupPoint: pickupPoint,
              onTap: () => _onPickupPointTapped(pickupPoint),
              isDark: isDark,
            ),
          );
        },
      ),
    );
  }
}
