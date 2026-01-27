import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../constants/region.dart'; // contains regionsList
import 'package:google_maps_flutter/google_maps_flutter.dart'; // For GeoPoint conversion
import '../LOCATION-SCREENS/pin_location_screen.dart'; // Ensure to import the PinLocationScreen
import 'package:flutter/services.dart';

/// Custom formatter that forces lowercase but capitalizes the first letter of each word (Title Case)
class _TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Convert all to lowercase first
    String text = newValue.text.toLowerCase();

    // Capitalize the first letter of each word
    text = text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    return TextEditingValue(
      text: text,
      selection: newValue.selection,
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
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digitsOnly.length > 10 ? digitsOnly.substring(0, 10) : digitsOnly;

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

class AddressesScreen extends StatefulWidget {
  @override
  _AddressesScreenState createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final String currentUserId;
  late AnimationController _fabAnimationController;

  Timer? _snackbarDebounceTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller first (before any early returns)
    // to ensure dispose() can safely access it
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Edge case: shouldn't happen, but safely exit
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    currentUserId = user.uid;
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _snackbarDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    CollectionReference addressesRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('addresses');

    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: addressesRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor:
                isDarkMode ? const Color(0xFF0F0F0F) : const Color(0xFFF8F9FA),
            appBar: _buildAppBar(localization, isDarkMode),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF00A36C)),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    localization.loading ?? 'Loading...',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final addresses = snapshot.data!.docs;

        // Animate FAB when data is loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (addresses.isNotEmpty && addresses.length < 4) {
            _fabAnimationController.forward();
          } else {
            _fabAnimationController.reverse();
          }
        });

        return Scaffold(
          backgroundColor:
              isDarkMode ? const Color(0xFF1C1A29) : const Color(0xFFF8F9FA),
          appBar: _buildAppBar(localization, isDarkMode),
          body: addresses.isEmpty
              ? _buildEmptyState(
                  context, localization, addressesRef, isDarkMode)
              : _buildAddressesList(
                  context, localization, addresses, addressesRef, isDarkMode),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
      AppLocalizations localization, bool isDarkMode) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle:
          isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      title: Text(
        localization.addresses,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: isDarkMode ? Colors.white : Colors.black,
          letterSpacing: -0.5,
        ),
      ),
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDarkMode ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppLocalizations localization,
    CollectionReference addressesRef,
    bool isDarkMode,
  ) {
    return Center(
      // ← wrap in Center
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min, // shrink to content height
          crossAxisAlignment:
              CrossAxisAlignment.center, // ensure children are centered
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00A36C).withOpacity(0.1),
                    const Color(0xFF00A36C).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(70),
                border: Border.all(
                  color: const Color(0xFF00A36C).withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Center(
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/empty-address.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.location_on_rounded,
                      size: 64,
                      color: const Color(0xFF00A36C).withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              localization.noSavedAddresses,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              localization.addFirstAddress ??
                  'Add your first address to get started',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _buildAddButton(context, localization, addressesRef, isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressesList(
      BuildContext context,
      AppLocalizations localization,
      List<DocumentSnapshot> addresses,
      CollectionReference addressesRef,
      bool isDarkMode) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization.savedAddresses ?? 'Saved Addresses',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${addresses.length}/4 ${localization.addresses ?? 'addresses'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.white60 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (addresses.length < 4)
                  _buildQuickAddButton(
                      context, localization, addressesRef, isDarkMode),
              ],
            ),
          ),
        ),
        if (isTablet)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 180,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final data = addresses[index].data() as Map<String, dynamic>;
                  final isPreferred = data['isPreferred'] ?? false;

                  return _buildAddressCard(
                    context,
                    data,
                    addresses[index],
                    addressesRef,
                    isPreferred,
                    isDarkMode,
                    localization,
                  );
                },
                childCount: addresses.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final data = addresses[index].data() as Map<String, dynamic>;
                  final isPreferred = data['isPreferred'] ?? false;

                  return Padding(
                    padding: EdgeInsets.only(
                        bottom: index == addresses.length - 1 ? 32 : 16),
                    child: _buildAddressCard(
                      context,
                      data,
                      addresses[index],
                      addressesRef,
                      isPreferred,
                      isDarkMode,
                      localization,
                    ),
                  );
                },
                childCount: addresses.length,
              ),
            ),
          ),
        // Add bottom padding for tablet grid
        if (isTablet)
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
      ],
    );
  }

  Widget _buildQuickAddButton(
      BuildContext context,
      AppLocalizations localization,
      CollectionReference addressesRef,
      bool isDarkMode) {
    return GestureDetector(
      onTap: () => _showAddressModal(context, addressesRef),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF00A36C),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              localization.addNew ?? 'Add New',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(
    BuildContext context,
    Map<String, dynamic> data,
    DocumentSnapshot doc,
    CollectionReference addressesRef,
    bool isPreferred,
    bool isDarkMode,
    AppLocalizations localization,
  ) {
    // Build subtitle with address details
    String subtitleText = '';
    if ((data['addressLine2'] ?? '').toString().isNotEmpty) {
      subtitleText += data['addressLine2'];
    }
    if ((data['city'] ?? '').toString().isNotEmpty) {
      if (subtitleText.isNotEmpty) subtitleText += ' • ';
      subtitleText += data['city'];
    }
    if ((data['phoneNumber'] ?? '').toString().isNotEmpty) {
      if (subtitleText.isNotEmpty) subtitleText += '\n';
      subtitleText += data['phoneNumber'];
    }

    return GestureDetector(
      onTap: () => _setAsPreferred(addressesRef, doc.id),
      child: Container(
        decoration: BoxDecoration(
          color:
              isDarkMode ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPreferred
                ? const Color(0xFF00A36C)
                : (isDarkMode
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isPreferred ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Preferred indicator
            if (isPreferred)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A36C),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        localization.preferred ?? 'Preferred',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Card content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: const Color(0xFF00A36C),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Padding(
                          // Add right padding when preferred to prevent overlap
                          padding:
                              EdgeInsets.only(right: isPreferred ? 120 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['addressLine1'] ?? '',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (subtitleText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitleText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Show coordinates if available
                      if (data['location'] != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localization.coordinates ?? 'Coordinates',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? Colors.white60
                                    : Colors.black45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatCoordinates(data['location']),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox.shrink(),
                      ],
                      Row(
                        children: [
                          _buildActionButton(
                            icon: Icons.edit_rounded,
                            color: const Color(0xFF00A36C),
                            backgroundColor:
                                const Color(0xFF00A36C).withOpacity(0.1),
                            onTap: () => _showAddressModal(
                              context,
                              addressesRef,
                              addressDoc: doc,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildActionButton(
                            icon: Icons.delete_outline_rounded,
                            color: Colors.red[400]!,
                            backgroundColor: Colors.red[50]!,
                            onTap: () => _deleteAddress(
                                addressesRef, doc.id, localization),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCoordinates(dynamic location) {
    if (location is GeoPoint) {
      return '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
    } else if (location is String) {
      return location;
    }
    return '';
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: color,
        ),
      ),
    );
  }

  Widget _buildAddButton(
    BuildContext context,
    AppLocalizations localization,
    CollectionReference addressesRef,
    bool isDarkMode,
  ) {
    return Container(
      width: 240,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ElevatedButton(
        onPressed: () => _showAddressModal(context, addressesRef),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00A36C),
          foregroundColor: Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(240, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 22),
            const SizedBox(width: 10),
            Text(
              localization.addNewAddress ?? 'Add New',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddressModal(BuildContext context, CollectionReference addressesRef,
      {DocumentSnapshot? addressDoc}) {
    final localization = AppLocalizations.of(context);

    showCupertinoModalPopup(
      context: context,
      builder: (context) => AddressFormModal(
        addressDoc: addressDoc,
        onSave: (Map<String, dynamic> addressData) async {
          // Check if we're at the limit
          final snapshot = await addressesRef.get();

          if (snapshot.docs.length >= 4 && addressDoc == null) {
            // Check if context is still valid before showing SnackBar
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localization.maxAddressesReached ??
                      'Maximum 4 addresses allowed'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
            return;
          }

          // If this is the first address, make it preferred
          if (snapshot.docs.isEmpty) {
            addressData['isPreferred'] = true;
          }

          try {
            if (addressDoc == null) {
              await addressesRef.add(addressData);
              // Check if context is still valid before showing SnackBar
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(localization.addressAdded ??
                        'Address added successfully'),
                    backgroundColor: const Color(0xFF00A36C),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            } else {
              await addressesRef.doc(addressDoc.id).update(addressData);
              // Check if context is still valid before showing SnackBar
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(localization.addressUpdated ??
                        'Address updated successfully'),
                    backgroundColor: const Color(0xFF00A36C),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            }
          } catch (e) {
            // Check if context is still valid before showing SnackBar
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(localization.errorOccurred ?? 'An error occurred'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _setAsPreferred(
      CollectionReference addressesRef, String docId) async {
    try {
      // First, remove preferred status from all addresses
      final snapshot = await addressesRef.get();
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isPreferred': false});
      }

      // Then set the selected one as preferred
      batch.update(addressesRef.doc(docId), {'isPreferred': true});

      await batch.commit();

      // Debounce snackbar messages to prevent spam
      _snackbarDebounceTimer?.cancel();
      _snackbarDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          // Check if widget is still mounted
          final localization = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  localization.preferredAddressSet ?? 'Preferred address set'),
              backgroundColor: const Color(0xFF00A36C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        // Check if widget is still mounted
        final localization = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localization.errorOccurred ?? 'An error occurred'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _deleteAddress(CollectionReference addressesRef, String docId,
      AppLocalizations localization) async {
    // Show Cupertino confirmation dialog
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text(localization.deleteAddress ?? 'Delete Address'),
        content: Text(localization.deleteAddressConfirmation ??
            'Are you sure you want to delete this address?'),
        actions: [
          CupertinoDialogAction(
            child: Text(
              localization.cancel,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: Text(localization.delete ?? 'Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await addressesRef.doc(docId).delete();
        // Check if context is still valid before showing SnackBar
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localization.addressDeleted ?? 'Address deleted'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        // Check if context is still valid before showing SnackBar
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localization.errorOccurred ?? 'An error occurred'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }
}

class AddressFormModal extends StatefulWidget {
  final DocumentSnapshot? addressDoc;
  final Function(Map<String, dynamic>) onSave;

  const AddressFormModal({Key? key, this.addressDoc, required this.onSave})
      : super(key: key);

  @override
  _AddressFormModalState createState() => _AddressFormModalState();
}

class _AddressFormModalState extends State<AddressFormModal> {
  late TextEditingController _addressLine1Controller;
  late TextEditingController _addressLine2Controller;
  late TextEditingController _phoneNumberController;
  String? _city;
  LatLng? _pinnedLocation;

  /// Format stored phone "05XXXXXXXXX" to display format "(5XX) XXX XX XX"
  String _formatPhoneForDisplay(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    // Remove leading 0 if present
    final digits = digitsOnly.startsWith('0') ? digitsOnly.substring(1) : digitsOnly;
    if (digits.length != 10) return phone; // Return as-is if not valid

    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)} ${digits.substring(6, 8)} ${digits.substring(8, 10)}';
  }

  @override
  void initState() {
    super.initState();
    _addressLine1Controller = TextEditingController(
      text: widget.addressDoc != null
          ? widget.addressDoc!.get('addressLine1') ?? ''
          : '',
    );
    _addressLine2Controller = TextEditingController(
      text: widget.addressDoc != null
          ? widget.addressDoc!.get('addressLine2') ?? ''
          : '',
    );
    _phoneNumberController = TextEditingController(
      text: widget.addressDoc != null
          ? _formatPhoneForDisplay(widget.addressDoc!.get('phoneNumber') ?? '')
          : '',
    );
    _city = widget.addressDoc != null
        ? widget.addressDoc!.get('city') ?? null
        : null;

    // If editing an existing address, try to retrieve previously saved location coordinates.
    if (widget.addressDoc != null && widget.addressDoc!.data() != null) {
      var data = widget.addressDoc!.data() as Map<String, dynamic>;
      if (data['location'] != null) {
        final loc = data['location'];
        if (loc is GeoPoint) {
          // Convert GeoPoint to LatLng.
          _pinnedLocation = LatLng(loc.latitude, loc.longitude);
        } else if (loc is String) {
          // In case it is stored as a comma-separated string: "lat,lng"
          final parts = loc.split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0]);
            final lng = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              _pinnedLocation = LatLng(lat, lng);
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final borderColor = Colors.grey[400]!;
    final placeholderStyle = TextStyle(
      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85 -
                    MediaQuery.of(context).viewInsets.bottom,
                maxWidth: isTablet ? 500 : double.infinity,
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDarkMode
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.addressDoc == null
                          ? localization.newAddress
                          : localization.editAddress,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Figtree',
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                  ),

                  // Content area - scrollable form fields
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Address Line 1
                          _buildTextField(
                            controller: _addressLine1Controller,
                            placeholder: localization.addressLine1,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            applyTitleCase: true,
                          ),
                          const SizedBox(height: 12),

                          // Address Line 2
                          _buildTextField(
                            controller: _addressLine2Controller,
                            placeholder: localization.addressLine2,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            applyTitleCase: true,
                          ),
                          const SizedBox(height: 12),

                          // Phone Number
                          _buildTextField(
                            controller: _phoneNumberController,
                            placeholder: '(5__) ___ __ __',
                            keyboardType: TextInputType.phone,
                            isDark: isDarkMode,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            inputFormatters: [_PhoneNumberFormatter()],
                          ),
                          const SizedBox(height: 12),

                          // City Selector
                          GestureDetector(
                            onTap: _showCityPicker,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: borderColor, width: 1),
                                borderRadius: BorderRadius.circular(8),
                                color: isDarkMode
                                    ? const Color.fromARGB(255, 45, 43, 61)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _city ?? localization.selectCity,
                                    style: TextStyle(
                                      color: _city != null
                                          ? (isDarkMode
                                              ? Colors.white
                                              : Colors.black)
                                          : (isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600]),
                                      fontSize: 16,
                                    ),
                                  ),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    color: isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Pin Location
                          GestureDetector(
                            onTap: _navigateToPinLocation,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: borderColor, width: 1),
                                borderRadius: BorderRadius.circular(8),
                                color: isDarkMode
                                    ? const Color.fromARGB(255, 45, 43, 61)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _pinnedLocation == null
                                          ? localization.markOnMap
                                          : '${_pinnedLocation!.latitude.toStringAsFixed(4)}, ${_pinnedLocation!.longitude.toStringAsFixed(4)}',
                                      style: TextStyle(
                                        color: _pinnedLocation != null
                                            ? (isDarkMode
                                                ? Colors.white
                                                : Colors.black)
                                            : (isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey[600]),
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.location_on_rounded,
                                    color: _pinnedLocation != null
                                        ? const Color(0xFF00A36C)
                                        : (isDarkMode
                                            ? Colors.grey[400]
                                            : Colors.grey[600]),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom buttons
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDarkMode
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                localization.cancel,
                                style: TextStyle(
                                  fontFamily: 'Figtree',
                                  color: isDarkMode ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoButton(
                              color: (_addressLine1Controller.text.isEmpty ||
                                      _phoneNumberController.text.isEmpty ||
                                      _city == null)
                                  ? CupertinoColors.inactiveGray
                                  : const Color(0xFF00A36C),
                              onPressed: (_addressLine1Controller.text.isEmpty ||
                                      _phoneNumberController.text.isEmpty ||
                                      _city == null)
                                  ? null
                                  : () {
                                      // Normalize phone: "(5XX) XXX XX XX" -> "05XXXXXXXXX"
                                      final normalizedPhone = '0${_phoneNumberController.text.replaceAll(RegExp(r'\D'), '')}';
                                      final Map<String, dynamic> addressData = {
                                        'addressLine1':
                                            _addressLine1Controller.text,
                                        'addressLine2':
                                            _addressLine2Controller.text,
                                        'phoneNumber': normalizedPhone,
                                        'city': _city,
                                      };
                                      if (_pinnedLocation != null) {
                                        addressData['location'] = GeoPoint(
                                          _pinnedLocation!.latitude,
                                          _pinnedLocation!.longitude,
                                        );
                                      }
                                      Navigator.pop(context);
                                      widget.onSave(addressData);
                                    },
                              child: Text(
                                localization.save,
                                style: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// Helper method to build text fields
  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required bool isDark,
    required Color borderColor,
    required TextStyle placeholderStyle,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool applyTitleCase = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final formatters = <TextInputFormatter>[
      if (applyTitleCase) _TitleCaseFormatter(),
      if (inputFormatters != null) ...inputFormatters,
    ];
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      maxLines: maxLines,
      padding: const EdgeInsets.all(12),
      inputFormatters: formatters.isNotEmpty ? formatters : null,
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

  void _showCityPicker() {
    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Step 1: Show main regions
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text(
            localization.selectMainRegion ?? 'Select District',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: mainRegions.map((mainRegion) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showSubregionPicker(mainRegion);
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
            onPressed: () => Navigator.pop(context),
            child: Text(
              localization.cancel,
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

  void _showSubregionPicker(String selectedMainRegion) {
    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                localization.selectSubregion ?? 'Select Subregion',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            // Option to select the main region itself
            CupertinoActionSheetAction(
              onPressed: () {
                setState(() {
                  _city = selectedMainRegion;
                });
                Navigator.pop(context);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_city_rounded,
                    color: const Color(0xFF00A36C),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$selectedMainRegion (${localization.mainRegion ?? 'District'})',
                    style: TextStyle(
                      color: const Color(0xFF00A36C),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Divider
            if (subregions.isNotEmpty)
              Container(
                height: 1,
                color: isDarkMode ? Colors.white24 : Colors.black12,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
            // Subregions
            ...subregions.map((subregion) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  setState(() {
                    _city = subregion;
                  });
                  Navigator.pop(context);
                },
                child: Text(
                  subregion,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
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
              _showCityPicker();
            },
            child: Text(
              '← ${localization.back ?? 'Back'}',
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

  Future<void> _navigateToPinLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PinLocationScreen(
          initialLocation: _pinnedLocation,
        ),
      ),
    );
    if (result != null && result is LatLng) {
      setState(() {
        _pinnedLocation = result;
      });
    }
  }
}
