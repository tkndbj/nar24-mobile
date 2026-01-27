import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/product_payment_provider.dart';
import '../../screens/LOCATION-SCREENS/pin_location_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../generated/l10n/app_localizations.dart';
// Import your regions list from your constants file:
import '../../constants/region.dart'; // <-- This file should expose "regionsList"

class AddressSectionWidget extends StatefulWidget {
  const AddressSectionWidget({Key? key}) : super(key: key);

  @override
  State<AddressSectionWidget> createState() => _AddressSectionWidgetState();
}

class _AddressSectionWidgetState extends State<AddressSectionWidget> {
  void _showRegionPicker(
      BuildContext context, ProductPaymentProvider provider) {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final buttonTextColor = isLight ? Colors.black : Colors.white;

    // Step 1: Show main regions
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text(
            l10n.selectMainRegion ?? 'Select Main Region',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Figtree',
              fontSize: 16,
            ),
          ),
          actions: mainRegions.map((mainRegion) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showSubregionPicker(context, provider, mainRegion);
              },
              child: Text(
                mainRegion,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Figtree',
                  fontSize: 16,
                ),
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: buttonTextColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSubregionPicker(BuildContext context,
      ProductPaymentProvider provider, String selectedMainRegion) {
    final l10n = AppLocalizations.of(context);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final buttonTextColor = isLight ? Colors.black : Colors.white;
    final subregions = regionHierarchy[selectedMainRegion] ?? [];

    // Step 2: Show subregions for the selected main region
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Column(
            children: [
              Text(
                selectedMainRegion,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Figtree',
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.selectSubregion ?? 'Select Subregion',
                style: TextStyle(
                  color: isLight ? Colors.black54 : Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Figtree',
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            // Option to select the main region itself
            CupertinoActionSheetAction(
              onPressed: () {
                provider.setRegion(selectedMainRegion);
                Navigator.pop(context);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_city_rounded,
                    color: const Color(0xFF0096FF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$selectedMainRegion (${l10n.mainRegion ?? 'Main Region'})',
                    style: TextStyle(
                      color: const Color(0xFF0096FF),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Figtree',
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            // Divider
            if (subregions.isNotEmpty)
              Container(
                height: 1,
                color: isLight ? Colors.black12 : Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
            // Subregions
            ...subregions.map((subregion) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  provider.setRegion(subregion);
                  Navigator.pop(context);
                },
                child: Text(
                  subregion,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Figtree',
                    fontSize: 16,
                  ),
                ),
              );
            }).toList(),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              // Go back to main region selection
              _showRegionPicker(context, provider);
            },
            child: Text(
              '← ${l10n.back ?? 'Back'}',
              style: TextStyle(
                color: buttonTextColor,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper method to safely convert location data to LatLng
  LatLng? _getLatLngFromLocationData(dynamic locationData) {
    if (locationData == null) return null;

    try {
      if (locationData is LatLng) {
        return locationData;
      } else if (locationData is Map<String, dynamic>) {
        final lat = locationData['latitude'];
        final lng = locationData['longitude'];
        if (lat != null && lng != null) {
          return LatLng(lat.toDouble(), lng.toDouble());
        }
      }
    } catch (e) {
      print('Error converting location data: $e');
    }

    return null;
  }

  // Helper method to convert LatLng to Map for storage
  Map<String, dynamic>? _getLocationDataFromLatLng(LatLng? latLng) {
    if (latLng == null) return null;
    return {
      'latitude': latLng.latitude,
      'longitude': latLng.longitude,
    };
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ProductPaymentProvider>(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (non-collapsible)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0096FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF0096FF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.shippingAddress,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content (always visible)
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: provider.addressFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.savedAddresses.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.savedAddresses,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...provider.savedAddresses.map((address) {
                            final isSelected =
                                provider.selectedAddressId == address['id'];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0096FF).withOpacity(0.05)
                                    : (isDark
                                        ? const Color(0xFF1C1A29)
                                        : Colors.grey.shade50),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF0096FF).withOpacity(0.3)
                                      : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                title: Text(
                                  '${address['addressLine1']}, ${address['city'] ?? address['region'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                onTap: () {
                                  // When selecting a saved address, properly handle the location data
                                  provider.onAddressSelected(address['id']);

                                  // Set the location from saved address data
                                  final locationData = address['location'];
                                  final latLng =
                                      _getLatLngFromLocationData(locationData);
                                  if (latLng != null) {
                                    provider.setSelectedLocation(latLng);
                                  }

                                  // Also populate other address fields if needed
                                  if (address['addressLine1'] != null) {
                                    provider.addressLine1Controller.text =
                                        address['addressLine1'];
                                  }
                                  if (address['addressLine2'] != null) {
                                    provider.addressLine2Controller.text =
                                        address['addressLine2'] ?? '';
                                  }
                                  if (address['region'] != null) {
                                    provider.setRegion(address['region']);
                                  }
                                  if (address['phoneNumber'] != null) {
                                    provider.phoneNumberController.text =
                                        address['phoneNumber'];
                                  }
                                },
                                leading: Radio<String?>(
                                  value: address['id'],
                                  groupValue: provider.selectedAddressId,
                                  onChanged: (value) {
                                    provider.onAddressSelected(value);

                                    // Handle location data when radio button is selected
                                    if (value != null) {
                                      final locationData = address['location'];
                                      final latLng = _getLatLngFromLocationData(
                                          locationData);
                                      if (latLng != null) {
                                        provider.setSelectedLocation(latLng);
                                      }

                                      // Populate form fields
                                      if (address['addressLine1'] != null) {
                                        provider.addressLine1Controller.text =
                                            address['addressLine1'];
                                      }
                                      if (address['addressLine2'] != null) {
                                        provider.addressLine2Controller.text =
                                            address['addressLine2'] ?? '';
                                      }
                                      if (address['region'] != null) {
                                        provider.setRegion(address['region']);
                                      }
                                      if (address['phoneNumber'] != null) {
                                        provider.phoneNumberController.text =
                                            address['phoneNumber'];
                                      }
                                    }
                                  },
                                  activeColor: const Color(0xFF0096FF),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  onPressed: () =>
                                      provider.removeAddress(address['id']),
                                  tooltip: l10n.remove,
                                  color: Colors.red.shade400,
                                ),
                              ),
                            );
                          }).toList(),
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: provider.selectedAddressId == null
                                  ? const Color(0xFF0096FF).withOpacity(0.05)
                                  : (isDark
                                      ? const Color(0xFF1C1A29)
                                      : Colors.grey.shade50),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: provider.selectedAddressId == null
                                    ? const Color(0xFF0096FF).withOpacity(0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              title: Text(
                                l10n.enterNewAddress,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              leading: Radio<String?>(
                                value: null,
                                groupValue: provider.selectedAddressId,
                                onChanged: provider.onAddressSelected,
                                activeColor: const Color(0xFF0096FF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    _buildCompactTextField(
                      controller: provider.addressLine1Controller,
                      label: l10n.addressLine1,
                      icon: Icons.home_outlined,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.fieldRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildCompactTextField(
                      controller: provider.addressLine2Controller,
                      label: l10n.addressLine2,
                      icon: Icons.business_outlined,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _showRegionPicker(context, provider),
                      child: AbsorbPointer(
                        child: _buildCompactTextField(
                          controller: TextEditingController(
                              text: provider.selectedRegion != null &&
                                      provider.selectedRegion!.trim().isNotEmpty
                                  ? provider.selectedRegion
                                  : ''),
                          label: l10n.region,
                          icon: Icons.map_outlined,
                          hintText: provider.selectedRegion == null ||
                                  provider.selectedRegion!.trim().isEmpty
                              ? l10n.region
                              : null,
                          validator: (value) {
                            if (provider.selectedRegion == null ||
                                provider.selectedRegion!.trim().isEmpty) {
                              return l10n.fieldRequired;
                            }
                            return null;
                          },
                          suffixIcon:
                              const Icon(Icons.arrow_drop_down, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactTextField(
                      controller: provider.phoneNumberController,
                      label: l10n.phoneNumber,
                      hintText: '(5__) ___ __ __',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_PhoneNumberFormatter()],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.fieldRequired;
                        }
                        // Check for 10 digits (formatted as "(XXX) XXX XX XX")
                        final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
                        if (digitsOnly.length != 10) {
                          return l10n.invalidPhoneNumber;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        final selectedLocation = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PinLocationScreen(
                              initialLocation: provider.selectedLocation,
                            ),
                          ),
                        );
                        if (selectedLocation != null) {
                          provider.setSelectedLocation(selectedLocation);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0096FF).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF0096FF).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0096FF).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_pin,
                                color: Color(0xFF0096FF),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.pinAddressOnMap,
                                    style: const TextStyle(
                                      color: Color(0xFF0096FF),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (provider.selectedLocation != null)
                                    Text(
                                      'Lat: ${provider.selectedLocation!.latitude.toStringAsFixed(4)}, '
                                      'Lng: ${provider.selectedLocation!.longitude.toStringAsFixed(4)}',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: Color(0xFF0096FF),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (provider.attemptedPayment &&
                        provider.selectedLocation == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          l10n.pinLocationRequired,
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (provider.selectedAddressId == null)
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C1A29)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CheckboxListTile(
                          value: provider.saveAddress,
                          onChanged: (value) {
                            provider.saveAddress = value ?? false;
                            provider.notifyListeners();
                          },
                          title: Text(
                            l10n.saveAddress,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          activeColor: const Color(0xFF0096FF),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
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

  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? Colors.white : Colors.black,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon,
            size: 18, color: isDark ? Colors.white : Colors.grey.shade600),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0096FF), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1A29) : Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: TextStyle(
            fontSize: 14, color: isDark ? Colors.white : Colors.grey.shade600),
        hintStyle: TextStyle(
            fontSize: 14, color: isDark ? Colors.white : Colors.grey.shade400),
      ),
    );
  }
}

/// Phone number formatter for Turkish format: (5XX) XXX XX XX
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digits
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limit to 10 digits
    final limited = digitsOnly.length > 10 ? digitsOnly.substring(0, 10) : digitsOnly;

    // Format as (XXX) XXX XX XX
    final buffer = StringBuffer();
    for (int i = 0; i < limited.length; i++) {
      if (i == 0) buffer.write('(');
      buffer.write(limited[i]);
      if (i == 2) buffer.write(') ');
      if (i == 5) buffer.write(' ');
      if (i == 7) buffer.write(' ');
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
