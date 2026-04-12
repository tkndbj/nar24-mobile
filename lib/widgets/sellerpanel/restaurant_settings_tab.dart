import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../constants/foodData.dart';
import '../../constants/region.dart';
import '../../utils/food_localization.dart';

// ─── Types ────────────────────────────────────────────────────────────────────

class MinOrderRegion {
  final String mainRegion;
  final String subregion;
  final double minOrderPrice;

  const MinOrderRegion({
    required this.mainRegion,
    required this.subregion,
    required this.minOrderPrice,
  });

  Map<String, dynamic> toMap() => {
        'mainRegion': mainRegion,
        'subregion': subregion,
        'minOrderPrice': minOrderPrice,
      };

  factory MinOrderRegion.fromMap(Map<String, dynamic> m) => MinOrderRegion(
        mainRegion: m['mainRegion'] as String? ?? '',
        subregion: m['subregion'] as String? ?? '',
        minOrderPrice: (m['minOrderPrice'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is MinOrderRegion &&
      mainRegion == other.mainRegion &&
      subregion == other.subregion &&
      minOrderPrice == other.minOrderPrice;

  @override
  int get hashCode => Object.hash(mainRegion, subregion, minOrderPrice);
}

class _WorkingHours {
  final String open;
  final String close;
  const _WorkingHours({required this.open, required this.close});

  @override
  bool operator ==(Object other) =>
      other is _WorkingHours && open == other.open && close == other.close;

  @override
  int get hashCode => Object.hash(open, close);
}

class _RestaurantSettings {
  final List<String> foodType;
  final List<String> cuisineTypes;
  final List<String> workingDays;
  final _WorkingHours workingHours;
  final List<MinOrderRegion> minOrderPrices;
  final bool isActive;

  const _RestaurantSettings({
    required this.foodType,
    required this.cuisineTypes,
    required this.workingDays,
    required this.workingHours,
    required this.minOrderPrices,
    required this.isActive,
  });

  bool equals(_RestaurantSettings other) {
    if (isActive != other.isActive) return false;
    if (workingHours != other.workingHours) return false;
    if (workingDays.length != other.workingDays.length) return false;
    if (!workingDays.toSet().containsAll(other.workingDays)) return false;
    if (foodType.length != other.foodType.length) return false;
    if (!foodType.toSet().containsAll(other.foodType)) return false;
    if (cuisineTypes.length != other.cuisineTypes.length) return false;
    if (!cuisineTypes.toSet().containsAll(other.cuisineTypes)) return false;
    if (minOrderPrices.length != other.minOrderPrices.length) return false;
    for (int i = 0; i < minOrderPrices.length; i++) {
      if (minOrderPrices[i] != other.minOrderPrices[i]) return false;
    }
    return true;
  }
}

// ─── Constants ────────────────────────────────────────────────────────────────

const _allDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _cuisineOptions = [
  'Turkish Cuisine',
  'Japanese Cuisine',
  'Chinese Cuisine',
  'Persian Cuisine',
  'Arabic Cuisine',
  'Italian Cuisine',
  'Korean Cuisine',
  'Vietnamese Cuisine',
  'Vegan / Vegetarian',
];

// ─── Main Widget ──────────────────────────────────────────────────────────────

class RestaurantSettingsTab extends StatefulWidget {
  final String restaurantId;

  const RestaurantSettingsTab({Key? key, required this.restaurantId})
      : super(key: key);

  @override
  State<RestaurantSettingsTab> createState() => _RestaurantSettingsTabState();
}

class _RestaurantSettingsTabState extends State<RestaurantSettingsTab> {
  final _firestore = FirebaseFirestore.instance;

  // Loading / saving
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Snapshot of what's persisted (to detect changes)
  _RestaurantSettings? _savedSettings;

  // Editable state
  List<String> _foodType = [];
  List<String> _cuisineTypes = [];
  List<String> _workingDays = [];
  String _openTime = '09:00';
  String _closeTime = '22:00';
  List<MinOrderRegion> _minOrderPrices = [];
  bool _isActive = true;

  // Region picker state
  String _selectedMainRegion = '';
  String _selectedSubregion = '';
  final _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  _RestaurantSettings get _current => _RestaurantSettings(
        foodType: List.from(_foodType),
        cuisineTypes: List.from(_cuisineTypes),
        workingDays: List.from(_workingDays),
        workingHours: _WorkingHours(open: _openTime, close: _closeTime),
        minOrderPrices: List.from(_minOrderPrices),
        isActive: _isActive,
      );

  bool get _hasChanges =>
      _savedSettings != null && !_current.equals(_savedSettings!);

  bool _isSubregionAdded(String sub) =>
      _minOrderPrices.any((e) => e.subregion == sub);

  List<String> get _availableSubregions => _selectedMainRegion.isNotEmpty
      ? (regionHierarchy[_selectedMainRegion] ?? [])
      : [];

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _fetchSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _firestore
          .collection('restaurants')
          .doc(widget.restaurantId)
          .get();

      if (!mounted) return;

      if (snap.exists) {
        final d = snap.data()!;
        final wh = d['workingHours'] as Map<String, dynamic>? ?? {};
        final settings = _RestaurantSettings(
          foodType: List<String>.from(d['foodType'] ?? []),
          cuisineTypes: List<String>.from(d['cuisineTypes'] ?? []),
          workingDays: List<String>.from(d['workingDays'] ?? []),
          workingHours: _WorkingHours(
            open: wh['open'] as String? ?? '09:00',
            close: wh['close'] as String? ?? '22:00',
          ),
          minOrderPrices: (d['minOrderPrices'] as List? ?? [])
              .map((e) => MinOrderRegion.fromMap(e as Map<String, dynamic>))
              .toList(),
          isActive: d['isActive'] as bool? ?? true,
        );

        setState(() {
          _savedSettings = settings;
          _foodType = List.from(settings.foodType);
          _cuisineTypes = List.from(settings.cuisineTypes);
          _workingDays = List.from(settings.workingDays);
          _openTime = settings.workingHours.open;
          _closeTime = settings.workingHours.close;
          _minOrderPrices = List.from(settings.minOrderPrices);
          _isActive = settings.isActive;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_hasChanges || _saving) return;
    setState(() => _saving = true);
    try {
      await _firestore
          .collection('restaurants')
          .doc(widget.restaurantId)
          .update({
        'foodType': _foodType,
        'cuisineTypes': _cuisineTypes,
        'workingDays': _workingDays,
        'workingHours': {'open': _openTime, 'close': _closeTime},
        'minOrderPrices': _minOrderPrices.map((e) => e.toMap()).toList(),
        'isActive': _isActive,
      });

      if (!mounted) return;
      setState(() {
        _savedSettings = _current;
        _saving = false;
      });
      _showSnackBar(AppLocalizations.of(context).saveSuccess, isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnackBar(AppLocalizations.of(context).saveError, isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontSize: 13)),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Toggle helpers ────────────────────────────────────────────────────────

  void _toggleDay(String day) => setState(() {
        _workingDays.contains(day)
            ? _workingDays.remove(day)
            : _workingDays.add(day);
      });

  void _toggleAllDays() => setState(() {
        _workingDays =
            _workingDays.length == _allDays.length ? [] : List.from(_allDays);
      });

  void _toggleCuisine(String c) => setState(() {
        _cuisineTypes.contains(c)
            ? _cuisineTypes.remove(c)
            : _cuisineTypes.add(c);
      });

  void _toggleFoodType(String f) => setState(() {
        _foodType.contains(f) ? _foodType.remove(f) : _foodType.add(f);
      });

  void _addMinOrderPrice() {
    final price = double.tryParse(_priceController.text);
    if (_selectedMainRegion.isEmpty ||
        _selectedSubregion.isEmpty ||
        price == null ||
        price <= 0 ||
        _isSubregionAdded(_selectedSubregion)) return;

    setState(() {
      _minOrderPrices.add(MinOrderRegion(
        mainRegion: _selectedMainRegion,
        subregion: _selectedSubregion,
        minOrderPrice: price,
      ));
      _selectedSubregion = '';
      _priceController.clear();
    });
  }

  void _removeMinOrderPrice(int index) =>
      setState(() => _minOrderPrices.removeAt(index));

  // ── Time picker ───────────────────────────────────────────────────────────

  Future<void> _pickTime({required bool isOpen}) async {
    final parts = (isOpen ? _openTime : _closeTime).split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? (isOpen ? 9 : 22),
      minute: int.tryParse(parts[1]) ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isOpen) {
        _openTime = formatted;
      } else {
        _closeTime = formatted;
      }
    });
  }

  // ── Food type bottom sheet ────────────────────────────────────────────────

  void _showFoodTypeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
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
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).selectFoodType,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close_rounded,
                            color: isDark ? Colors.white70 : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Category list
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: FoodCategoryData.kCategories.map((cat) {
                      final isSelected = _foodType.contains(cat);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) {
                          _toggleFoodType(cat);
                          setSheet(() {});
                        },
                        title: Text(
                          _getCategoryName(cat),
                          style: TextStyle(fontSize: 13),
                        ),
                        activeColor: const Color(0xFF667EEA),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                ),
                // Confirm button
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, MediaQuery.of(ctx).padding.bottom + 12),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(
                      AppLocalizations.of(context)
                          .okCategoriesSelected(_foodType.length),
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _getCategoryName(String key) {
    return localizeCategory(key, AppLocalizations.of(context));
  }

  // Cuisine localization helpers
  String _cuisineLabel(String cuisine) {
    final l10n = AppLocalizations.of(context);
    switch (cuisine) {
      case 'Turkish Cuisine':
        return l10n.cuisineTypeTurkish;
      case 'Japanese Cuisine':
        return l10n.cuisineTypeJapanese;
      case 'Chinese Cuisine':
        return l10n.cuisineTypeChinese;
      case 'Persian Cuisine':
        return l10n.cuisineTypePersian;
      case 'Arabic Cuisine':
        return l10n.cuisineTypeArabic;
      case 'Italian Cuisine':
        return l10n.cuisineTypeItalian;
      case 'Korean Cuisine':
        return l10n.cuisineTypeKorean;
      case 'Vietnamese Cuisine':
        return l10n.cuisineTypeVietnamese;
      case 'Vegan / Vegetarian':
        return l10n.cuisineTypeVeganVegetarian;
      default:
        return cuisine;
    }
  }

  String _dayLabel(String day) {
    final l10n = AppLocalizations.of(context);
    switch (day) {
      case 'Monday':
        return l10n.dayMonday;
      case 'Tuesday':
        return l10n.dayTuesday;
      case 'Wednesday':
        return l10n.dayWednesday;
      case 'Thursday':
        return l10n.dayThursday;
      case 'Friday':
        return l10n.dayFriday;
      case 'Saturday':
        return l10n.daySaturday;
      case 'Sunday':
        return l10n.daySunday;
      default:
        return day.substring(0, 3);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) return _buildLoadingState(isDark);
    if (_error != null) return _buildErrorState();

    return Stack(
      children: [
        RefreshIndicator(
          color: const Color(0xFFFF6200),
          onRefresh: _fetchSettings,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              children: [
                _buildActiveStatusSection(isDark),
                const SizedBox(height: 12),
                _buildFoodTypeSection(isDark),
                const SizedBox(height: 12),
                _buildCuisineTypeSection(isDark),
                const SizedBox(height: 12),
                _buildMinOrderSection(isDark),
                const SizedBox(height: 12),
                _buildWorkingScheduleSection(isDark),
              ],
            ),
          ),
        ),
        // Sticky save button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildSaveButton(isDark),
        ),
      ],
    );
  }

  // ── Section: Active Status ─────────────────────────────────────────────────

  Widget _buildActiveStatusSection(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.power_settings_new_rounded,
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
            title: l10n.restaurantStatus,
            subtitle: l10n.restaurantStatusDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() => _isActive = !_isActive),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _isActive
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isActive
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFFFCA5A5),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isActive ? l10n.active : l10n.inactive,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _isActive
                          ? const Color(0xFF065F46)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                  // Custom toggle switch
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _isActive
                          ? const Color(0xFF10B981)
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          top: 3,
                          left: _isActive ? 21 : 3,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: Food Type ─────────────────────────────────────────────────────

  Widget _buildFoodTypeSection(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.restaurant_menu_rounded,
            iconBg: const Color(0xFFF5F3FF),
            iconColor: const Color(0xFF7C3AED),
            title: l10n.foodType,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          // Selector button
          GestureDetector(
            onTap: _showFoodTypeSheet,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.grey.withOpacity(0.25),
                ),
              ),
              child: Text(
                _foodType.isEmpty
                    ? l10n.selectFoodType
                    : l10n.categoriesSelected(_foodType.length),
                style: TextStyle(
                  fontSize: 13,
                  color: _foodType.isEmpty
                      ? Colors.grey[400]
                      : (isDark ? Colors.white : Colors.grey[900]),
                  fontWeight:
                      _foodType.isEmpty ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),
          ),
          // Chips for selected food types
          if (_foodType.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _foodType.map((ft) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getCategoryName(ft),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF6D28D9),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _toggleFoodType(ft),
                        child: const Icon(Icons.close_rounded,
                            size: 13, color: Color(0xFF7C3AED)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: Cuisine Type ──────────────────────────────────────────────────

  Widget _buildCuisineTypeSection(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.language_rounded,
            iconBg: const Color(0xFFEEF2FF),
            iconColor: const Color(0xFF4F46E5),
            title: l10n.cuisineType,
            subtitle: l10n.selectCuisineType,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _cuisineOptions.map((cuisine) {
              final isSelected = _cuisineTypes.contains(cuisine);
              return GestureDetector(
                onTap: () => _toggleCuisine(cuisine),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEEF2FF)
                        : (isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF818CF8)
                          : (isDark
                              ? Colors.white.withOpacity(0.12)
                              : Colors.grey.withOpacity(0.25)),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    _cuisineLabel(cuisine),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF3730A3)
                          : (isDark ? Colors.grey[300] : Colors.grey[500]),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Section: Min Order Price ───────────────────────────────────────────────

  Widget _buildMinOrderSection(bool isDark) {
    final l10n = AppLocalizations.of(context);
    final canAdd = _selectedMainRegion.isNotEmpty &&
        _selectedSubregion.isNotEmpty &&
        _priceController.text.isNotEmpty &&
        !_isSubregionAdded(_selectedSubregion);

    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.attach_money_rounded,
            iconBg: const Color(0xFFECFDF5),
            iconColor: const Color(0xFF059669),
            title: l10n.minOrderPriceByRegion,
            subtitle: l10n.minOrderPriceDescription,
            isDark: isDark,
          ),
          const SizedBox(height: 14),

          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.minOrderPriceWarning,
                    style: TextStyle(
                        fontSize: 12, color: const Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Main region dropdown
          _buildDropdownLabel(l10n.mainRegion, isDark),
          const SizedBox(height: 6),
          _buildDropdown(
            hint: l10n.selectMainRegion,
            value: _selectedMainRegion.isEmpty ? null : _selectedMainRegion,
            items: mainRegions,
            isDark: isDark,
            onChanged: (v) => setState(() {
              _selectedMainRegion = v ?? '';
              _selectedSubregion = '';
            }),
          ),
          const SizedBox(height: 10),

          // Subregion dropdown
          _buildDropdownLabel(l10n.subRegion, isDark),
          const SizedBox(height: 6),
          _buildDropdown(
            hint: l10n.selectSubRegion,
            value: _selectedSubregion.isEmpty ? null : _selectedSubregion,
            items: _availableSubregions,
            isDark: isDark,
            enabled: _selectedMainRegion.isNotEmpty,
            disabledItems: _minOrderPrices.map((e) => e.subregion).toSet(),
            onChanged: (v) => setState(() => _selectedSubregion = v ?? ''),
          ),
          const SizedBox(height: 10),

          // Price input + Add button
          _buildDropdownLabel('${l10n.minPrice} (TL)', isDark),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceController,
                  enabled: _selectedSubregion.isNotEmpty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(
                        fontSize: 13, color: Colors.grey[400]),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.withOpacity(0.25)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.withOpacity(0.25)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF10B981), width: 2),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.grey.withOpacity(0.12)),
                    ),
                    filled: true,
                    fillColor: _selectedSubregion.isEmpty
                        ? (isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.grey[50])
                        : (isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: canAdd ? _addMinOrderPrice : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: canAdd ? const Color(0xFF10B981) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: canAdd ? Colors.white : Colors.grey[400],
                    size: 22,
                  ),
                ),
              ),
            ],
          ),

          // Added regions list
          if (_minOrderPrices.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '${l10n.addedRegions} (${_minOrderPrices.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(_minOrderPrices.length, (i) {
              final entry = _minOrderPrices[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF10B981).withOpacity(0.08)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF6EE7B7).withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.mainRegion,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.subregion,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.grey[800],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${entry.minOrderPrice.toStringAsFixed(2)} TL',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.grey[900],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeMinOrderPrice(i),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.delete_outline_rounded,
                            size: 15, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // ── Section: Working Schedule ──────────────────────────────────────────────

  Widget _buildWorkingScheduleSection(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return _SectionCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.calendar_today_rounded,
            iconBg: const Color(0xFFFFF7ED),
            iconColor: const Color(0xFFEA580C),
            title: l10n.workingSchedule,
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // Working days header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.workingDays,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[400],
                  letterSpacing: 0.5,
                ),
              ),
              GestureDetector(
                onTap: _toggleAllDays,
                child: Text(
                  _workingDays.length == _allDays.length
                      ? l10n.deselectAll
                      : l10n.selectAll,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Day chips grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _allDays.map((day) {
              final isSelected = _workingDays.contains(day);
              return GestureDetector(
                onTap: () => _toggleDay(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFF7ED)
                        : (isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFDBA74)
                          : (isDark
                              ? Colors.white.withOpacity(0.12)
                              : Colors.grey.withOpacity(0.25)),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    _dayLabel(day).substring(0, 3),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFC2410C)
                          : (isDark ? Colors.grey[300] : Colors.grey[500]),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Working hours
          Text(
            l10n.workingHours,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _buildTimePicker(
                      isOpen: true, isDark: isDark, label: l10n.openTime)),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text('  –  ',
                    style: TextStyle(
                        color: Colors.grey[300], fontWeight: FontWeight.w500)),
              ),
              Expanded(
                  child: _buildTimePicker(
                      isOpen: false, isDark: isDark, label: l10n.closeTime)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(
      {required bool isOpen, required bool isDark, required String label}) {
    final time = isOpen ? _openTime : _closeTime;
    return Column(
      children: [
        GestureDetector(
          onTap: () => _pickTime(isOpen: isOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.grey.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 16, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Text(time,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.grey[800],
                    )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────

  Widget _buildSaveButton(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).scaffoldBackgroundColor.withOpacity(0.95)
            : Colors.white.withOpacity(0.95),
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.15))),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: _hasChanges && !_saving ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasChanges
                ? const Color(0xFFEA580C)
                : (isDark ? Colors.white10 : Colors.grey[100]),
            foregroundColor: _hasChanges ? Colors.white : Colors.grey[400],
            disabledBackgroundColor: isDark ? Colors.white10 : Colors.grey[100],
            disabledForegroundColor: Colors.grey[400],
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: _hasChanges ? 3 : 0,
            shadowColor: const Color(0xFFEA580C).withOpacity(0.3),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _hasChanges ? Icons.save_rounded : Icons.check_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _saving
                          ? l10n.saving
                          : _hasChanges
                              ? l10n.saveChanges
                              : l10n.noChanges,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── Shared dropdown builder ────────────────────────────────────────────────

  Widget _buildDropdownLabel(String label, bool isDark) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[400],
          letterSpacing: 0.5,
        ),
      );

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required bool isDark,
    required void Function(String?) onChanged,
    bool enabled = true,
    Set<String> disabledItems = const {},
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.12)),
        ),
        filled: true,
        fillColor: !enabled
            ? (isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50])
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
      ),
      style: TextStyle(
          fontSize: 13, color: isDark ? Colors.white : Colors.grey[900]),
      dropdownColor: isDark ? const Color(0xFF1E1B2E) : Colors.white,
      hint: Text(hint,
          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      items: enabled
          ? items.map((item) {
              final isDisabled = disabledItems.contains(item);
              return DropdownMenuItem(
                value: item,
                enabled: !isDisabled,
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDisabled
                        ? Colors.grey[400]
                        : (isDark ? Colors.white : Colors.grey[900]),
                  ),
                ),
              );
            }).toList()
          : [],
      onChanged: enabled ? onChanged : null,
    );
  }

  // ── Loading / Error ────────────────────────────────────────────────────────

  Widget _buildLoadingState(bool isDark) {
    final base = isDark ? const Color(0xFF28253A) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C394E) : Colors.grey.shade100;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
            ),
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
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).fetchError,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchSettings,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).retry),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6200)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Sub-widgets ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.grey.withOpacity(0.12),
        ),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isDark;

  const _SectionHeader({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

