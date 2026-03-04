// lib/widgets/restaurants/food_location_picker.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../constants/region.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../models/food_address.dart';
import '../../screens/LOCATION-SCREENS/pin_location_screen.dart';
import '../../user_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a bottom sheet for selecting / adding a food delivery address.
/// Returns the selected [FoodAddress] on confirm, or null on dismiss.
///
/// When [isDismissible] is false the user cannot swipe-down, tap the barrier,
/// or press back to close the sheet — they must pick an address.
Future<FoodAddress?> showFoodLocationPicker(
  BuildContext context, {
  bool isDismissible = true,
}) {
  return showModalBottomSheet<FoodAddress>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    builder: (_) => PopScope(
      canPop: isDismissible,
      child: const _FoodLocationPickerSheet(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVED ADDRESS MODEL (matches food_checkout_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _SavedAddress {
  final String id;
  final String addressLine1;
  final String addressLine2;
  final String phoneNumber;
  final String city;
  final LatLng? location;

  const _SavedAddress({
    required this.id,
    required this.addressLine1,
    required this.addressLine2,
    required this.phoneNumber,
    required this.city,
    this.location,
  });

  factory _SavedAddress.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    LatLng? loc;
    final l = d['location'];
    if (l is GeoPoint) {
      loc = LatLng(l.latitude, l.longitude);
    } else if (l is Map<String, dynamic>) {
      loc = LatLng(
        (l['latitude'] as num).toDouble(),
        (l['longitude'] as num).toDouble(),
      );
    }
    return _SavedAddress(
      id: doc.id,
      addressLine1: (d['addressLine1'] as String?) ?? '',
      addressLine2: (d['addressLine2'] as String?) ?? '',
      phoneNumber: (d['phoneNumber'] as String?) ?? '',
      city: (d['city'] as String?) ?? '',
      location: loc,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT FORMATTERS (same as addresses_screen.dart — private, can't import)
// ─────────────────────────────────────────────────────────────────────────────

class _TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    String text = newValue.text.toLowerCase();
    text = text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
    return TextEditingValue(text: text, selection: newValue.selection);
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited =
        digitsOnly.length > 10 ? digitsOnly.substring(0, 10) : digitsOnly;

    final buf = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 0) buf.write('(');
      buf.write(limited[i]);
      if (i == 2) buf.write(') ');
      if (i == 5) buf.write(' ');
      if (i == 7) buf.write(' ');
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _FoodLocationPickerSheet extends StatefulWidget {
  const _FoodLocationPickerSheet();

  @override
  State<_FoodLocationPickerSheet> createState() =>
      _FoodLocationPickerSheetState();
}

class _FoodLocationPickerSheetState extends State<_FoodLocationPickerSheet> {
  List<_SavedAddress>? _addresses;
  String? _selectedAddressId;
  bool _showNewForm = false;
  bool _saving = false;

  // New-address form controllers
  final _addr1Controller = TextEditingController();
  final _addr2Controller = TextEditingController();
  final _phoneController = TextEditingController();
  String? _newCity;
  LatLng? _newPinnedLocation;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _addr1Controller.dispose();
    _addr2Controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = context.read<UserProvider>().user?.uid;
    if (uid == null) return;

    // Load saved addresses
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses')
        .get();

    if (!mounted) return;

    final addresses = snap.docs
        .map((d) =>
            _SavedAddress.fromDoc(d as DocumentSnapshot<Map<String, dynamic>>))
        .toList();

    // Read current foodAddress from UserProvider
    final profileData = context.read<UserProvider>().profileData;
    final rawFoodAddress = profileData?['foodAddress'] as Map<String, dynamic>?;
    final currentId = rawFoodAddress?['addressId'] as String?;

    setState(() {
      _addresses = addresses;
      _selectedAddressId = currentId;
    });
  }

  bool get _isNewFormValid =>
      _addr1Controller.text.isNotEmpty &&
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length == 10 &&
      _newCity != null;

  Future<void> _confirmSelection() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.user?.uid;
      if (uid == null) return;

      FoodAddress foodAddress;

      if (_showNewForm) {
        // Save new address to subcollection first
        final normalizedPhone =
            '0${_phoneController.text.replaceAll(RegExp(r'\D'), '')}';
        final addressData = <String, dynamic>{
          'addressLine1': _addr1Controller.text,
          'addressLine2': _addr2Controller.text,
          'phoneNumber': normalizedPhone,
          'city': _newCity,
        };
        if (_newPinnedLocation != null) {
          addressData['location'] = GeoPoint(
            _newPinnedLocation!.latitude,
            _newPinnedLocation!.longitude,
          );
        }

        // Check limit
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('addresses')
            .get();
        if (existing.docs.length >= 4) {
          if (mounted) {
            final loc = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc.maxAddressesReached),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          setState(() => _saving = false);
          return;
        }

        // If first address, mark as preferred
        if (existing.docs.isEmpty) {
          addressData['isPreferred'] = true;
        }

        final newDocRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('addresses')
            .add(addressData);

        final derivedMainRegion = getMainRegion(_newCity!) ?? _newCity!;

        foodAddress = FoodAddress(
          addressId: newDocRef.id,
          addressLine1: _addr1Controller.text,
          addressLine2: _addr2Controller.text,
          city: _newCity!,
          mainRegion: derivedMainRegion,
          phoneNumber: normalizedPhone,
          location: _newPinnedLocation != null
              ? GeoPoint(
                  _newPinnedLocation!.latitude,
                  _newPinnedLocation!.longitude,
                )
              : null,
        );
      } else {
        // Use selected existing address
        final addr = _addresses!
            .cast<_SavedAddress?>()
            .firstWhere((a) => a!.id == _selectedAddressId, orElse: () => null);
        if (addr == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).errorOccurred),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          setState(() => _saving = false);
          return;
        }
        final derivedMainRegion = getMainRegion(addr.city) ?? addr.city;

        foodAddress = FoodAddress(
          addressId: addr.id,
          addressLine1: addr.addressLine1,
          addressLine2: addr.addressLine2,
          city: addr.city,
          mainRegion: derivedMainRegion,
          phoneNumber: addr.phoneNumber,
          location: addr.location != null
              ? GeoPoint(
                  addr.location!.latitude,
                  addr.location!.longitude,
                )
              : null,
        );
      }

      // Write to user doc
      await userProvider.updateProfileData({
        'foodAddress': foodAddress.toMap(),
      });

      if (!mounted) return;
      Navigator.pop(context, foodAddress);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).addressSelectedSuccess),
          backgroundColor: const Color(0xFF00A36C),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).errorOccurred),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final loc = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF1C1A29)
                : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.delivery_dining_rounded,
                      color: const Color(0xFF00A36C),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.foodDeliveryAddress,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDarkMode ? Colors.white : Colors.black87,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            loc.selectDeliveryAddress,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
              ),

              // Content
              Expanded(
                child: _addresses == null
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00A36C)),
                          strokeWidth: 3,
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        children: [
                          // Saved addresses
                          if (_addresses!.isNotEmpty && !_showNewForm)
                            ..._addresses!.map((addr) => _AddressCard(
                                  address: addr,
                                  isSelected:
                                      addr.id == _selectedAddressId,
                                  onTap: () => setState(() {
                                    _selectedAddressId = addr.id;
                                    _showNewForm = false;
                                  }),
                                )),

                          // Empty state
                          if (_addresses!.isEmpty && !_showNewForm)
                            _buildEmptyState(loc, isDarkMode),

                          // "Add New" button (when not showing form)
                          if (!_showNewForm && _addresses!.length < 4)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 8, bottom: 16),
                              child: _buildAddNewButton(loc, isDarkMode),
                            ),

                          // Inline new-address form
                          if (_showNewForm)
                            _InlineAddressForm(
                              addr1Controller: _addr1Controller,
                              addr2Controller: _addr2Controller,
                              phoneController: _phoneController,
                              city: _newCity,
                              pinnedLocation: _newPinnedLocation,
                              onCityChanged: (city) =>
                                  setState(() => _newCity = city),
                              onLocationChanged: (loc) =>
                                  setState(() => _newPinnedLocation = loc),
                              onCancel: () => setState(() {
                                _showNewForm = false;
                                _addr1Controller.clear();
                                _addr2Controller.clear();
                                _phoneController.clear();
                                _newCity = null;
                                _newPinnedLocation = null;
                              }),
                              onFieldChanged: () => setState(() {}),
                            ),
                        ],
                      ),
              ),

              // Bottom confirm button
              SafeArea(
                top: false,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: CupertinoButton(
                      color: _canConfirm
                          ? const Color(0xFF00A36C)
                          : (isDarkMode
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _canConfirm ? _confirmSelection : null,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text(
                              loc.useThisAddress,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                fontFamily: 'Figtree',
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _canConfirm {
    if (_saving) return false;
    if (_showNewForm) return _isNewFormValid;
    return _selectedAddressId != null;
  }

  Widget _buildEmptyState(AppLocalizations loc, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.location_off_rounded,
            size: 56,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 16),
          Text(
            loc.noSavedAddresses,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            loc.addAddressHint,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddNewButton(AppLocalizations loc, bool isDarkMode) {
    return GestureDetector(
      onTap: () => setState(() => _showNewForm = true),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00A36C).withValues(alpha: 0.4),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF00A36C).withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded,
                color: Color(0xFF00A36C), size: 20),
            const SizedBox(width: 8),
            Text(
              loc.newAddress,
              style: const TextStyle(
                color: Color(0xFF00A36C),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADDRESS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final _SavedAddress address;
  final bool isSelected;
  final VoidCallback onTap;

  const _AddressCard({
    required this.address,
    required this.isSelected,
    required this.onTap,
  });

  String _formatPhoneForDisplay(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final d = digits.startsWith('0') ? digits.substring(1) : digits;
    if (d.length != 10) return phone;
    return '(${d.substring(0, 3)}) ${d.substring(3, 6)} ${d.substring(6, 8)} ${d.substring(8, 10)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    String subtitle = '';
    if (address.addressLine2.isNotEmpty) subtitle += address.addressLine2;
    if (address.city.isNotEmpty) {
      if (subtitle.isNotEmpty) subtitle += ' • ';
      subtitle += address.city;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color.fromARGB(255, 33, 31, 49)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A36C)
                : (isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (!isDarkMode)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          children: [
            // Selection indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00A36C)
                      : (isDarkMode ? Colors.white30 : Colors.black26),
                  width: 2,
                ),
                color: isSelected ? const Color(0xFF00A36C) : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Address details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.addressLine1,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (address.phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      _formatPhoneForDisplay(address.phoneNumber),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Location indicator
            if (address.location != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: const Color(0xFF00A36C).withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INLINE ADDRESS FORM
// ─────────────────────────────────────────────────────────────────────────────

class _InlineAddressForm extends StatelessWidget {
  final TextEditingController addr1Controller;
  final TextEditingController addr2Controller;
  final TextEditingController phoneController;
  final String? city;
  final LatLng? pinnedLocation;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<LatLng?> onLocationChanged;
  final VoidCallback onCancel;
  final VoidCallback onFieldChanged;

  const _InlineAddressForm({
    required this.addr1Controller,
    required this.addr2Controller,
    required this.phoneController,
    required this.city,
    required this.pinnedLocation,
    required this.onCityChanged,
    required this.onLocationChanged,
    required this.onCancel,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = Colors.grey[400]!;
    final placeholderStyle = TextStyle(
      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with cancel
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              loc.newAddress,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: onCancel,
              child: Text(
                loc.cancel,
                style: TextStyle(
                  color: isDarkMode ? Colors.white60 : Colors.black45,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Address Line 1
        _buildField(
          controller: addr1Controller,
          placeholder: loc.addressLine1,
          isDark: isDarkMode,
          borderColor: borderColor,
          placeholderStyle: placeholderStyle,
          applyTitleCase: true,
        ),
        const SizedBox(height: 10),

        // Address Line 2
        _buildField(
          controller: addr2Controller,
          placeholder: loc.addressLine2,
          isDark: isDarkMode,
          borderColor: borderColor,
          placeholderStyle: placeholderStyle,
          applyTitleCase: true,
        ),
        const SizedBox(height: 10),

        // Phone
        _buildField(
          controller: phoneController,
          placeholder: '(5__) ___ __ __',
          isDark: isDarkMode,
          borderColor: borderColor,
          placeholderStyle: placeholderStyle,
          keyboardType: TextInputType.phone,
          formatters: [_PhoneNumberFormatter()],
        ),
        const SizedBox(height: 10),

        // City selector
        GestureDetector(
          onTap: () => _showCityPicker(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(8),
              color: isDarkMode
                  ? const Color.fromARGB(255, 45, 43, 61)
                  : Colors.grey.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  city ?? loc.selectCity,
                  style: TextStyle(
                    color: city != null
                        ? (isDarkMode ? Colors.white : Colors.black)
                        : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                    fontSize: 16,
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Pin location
        GestureDetector(
          onTap: () => _navigateToPinLocation(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(8),
              color: isDarkMode
                  ? const Color.fromARGB(255, 45, 43, 61)
                  : Colors.grey.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    pinnedLocation == null
                        ? loc.markOnMap
                        : '${pinnedLocation!.latitude.toStringAsFixed(4)}, ${pinnedLocation!.longitude.toStringAsFixed(4)}',
                    style: TextStyle(
                      color: pinnedLocation != null
                          ? (isDarkMode ? Colors.white : Colors.black)
                          : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.location_on_rounded,
                  color: pinnedLocation != null
                      ? const Color(0xFF00A36C)
                      : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String placeholder,
    required bool isDark,
    required Color borderColor,
    required TextStyle placeholderStyle,
    TextInputType? keyboardType,
    bool applyTitleCase = false,
    List<TextInputFormatter>? formatters,
  }) {
    final allFormatters = <TextInputFormatter>[
      if (applyTitleCase) _TitleCaseFormatter(),
      if (formatters != null) ...formatters,
    ];

    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      padding: const EdgeInsets.all(12),
      inputFormatters: allFormatters.isNotEmpty ? allFormatters : null,
      onChanged: (_) => onFieldChanged(),
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 16,
      ),
      placeholderStyle: placeholderStyle,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(8),
        color: isDark
            ? const Color.fromARGB(255, 45, 43, 61)
            : Colors.grey.shade50,
      ),
      cursorColor: isDark ? Colors.white : Colors.black,
    );
  }

  void _showCityPicker(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext ctx) {
        return CupertinoActionSheet(
          title: Text(
            loc.selectMainRegion,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: mainRegions.map((mainRegion) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showSubregionPicker(context, mainRegion);
              },
              child: Text(
                mainRegion,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              loc.cancel,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSubregionPicker(BuildContext context, String selectedMainRegion) {
    final loc = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subregions = regionHierarchy[selectedMainRegion] ?? [];

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext ctx) {
        return CupertinoActionSheet(
          title: Column(
            children: [
              Text(
                selectedMainRegion,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                loc.selectSubregion,
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                onCityChanged(selectedMainRegion);
                Navigator.pop(ctx);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_city_rounded,
                      color: Color(0xFF00A36C), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '$selectedMainRegion (${loc.mainRegion})',
                    style: const TextStyle(
                      color: Color(0xFF00A36C),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ...subregions.map((subregion) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  onCityChanged(subregion);
                  Navigator.pop(ctx);
                },
                child: Text(
                  subregion,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                ),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showCityPicker(context);
            },
            child: Text(
              '← ${loc.back}',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToPinLocation(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinLocationScreen(
          initialLocation: pinnedLocation,
        ),
      ),
    );
    if (result is LatLng) {
      onLocationChanged(result);
    }
  }
}
