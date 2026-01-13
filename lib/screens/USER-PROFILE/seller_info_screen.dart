// lib/screens/seller_info_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../LOCATION-SCREENS/pin_location_screen.dart';

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

class SellerInfoScreen extends StatefulWidget {
  const SellerInfoScreen({Key? key}) : super(key: key);

  @override
  _SellerInfoScreenState createState() => _SellerInfoScreenState();
}

class _SellerInfoScreenState extends State<SellerInfoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final String currentUserId;

  @override
  void initState() {
    super.initState();

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
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final docRef = _firestore.collection('users').doc(currentUserId);

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF1C1A29) : const Color(0xFFF8F9FA),
      appBar: _buildAppBar(localization, isDarkMode),
      body: StreamBuilder<DocumentSnapshot>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
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
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final sellerInfo = (data != null &&
                  data.containsKey('sellerInfo') &&
                  data['sellerInfo'] != null
              ? Map<String, dynamic>.from(data['sellerInfo'])
              : null);

          if (sellerInfo == null) {
            return _buildEmptyState(
              context,
              localization,
              docRef,
              isDarkMode,
            );
          }

          return _buildSellerInfoCard(
              context, localization, sellerInfo, docRef, isDarkMode);
        },
      ),
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
        localization.sellerInfo,
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
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
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
    DocumentReference docRef,
    bool isDarkMode,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
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
                    'assets/images/credit-card-payment.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, error, stack) {
                      return Icon(
                        Icons.account_balance_rounded,
                        size: 64,
                        color: const Color(0xFF00A36C).withOpacity(0.7),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              localization.noSellerInfo,
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
              localization.addSellerInfoDescription ??
                  'Add your seller information to start selling',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _buildAddButton(context, localization, docRef, isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerInfoCard(
    BuildContext context,
    AppLocalizations localization,
    Map<String, dynamic> sellerInfo,
    DocumentReference docRef,
    bool isDarkMode,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.sellerInformation ?? 'Seller Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localization.yourSellerDetails ?? 'Your seller details',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.black.withOpacity(0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                'assets/images/credit-card-payment.png',
                                width: 64,
                                height: 64,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${sellerInfo['ibanOwnerName'] ?? ''} ${sellerInfo['ibanOwnerSurname'] ?? ''}'
                                    .trim(),
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
                              const SizedBox(height: 4),
                              Text(
                                '${localization.phoneNumber}: ${sellerInfo['phone'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? Colors.white70
                                      : Colors.black54,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              if (sellerInfo['latitude'] != null &&
                                  sellerInfo['longitude'] != null)
                                Text(
                                  '${localization.location ?? 'Location'}: ${sellerInfo['latitude'].toStringAsFixed(4)}, ${sellerInfo['longitude'].toStringAsFixed(4)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (sellerInfo['address'] != null &&
                        sellerInfo['address'].toString().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.05)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.white.withOpacity(0.1)
                                : Colors.grey[200]!,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: isDarkMode
                                      ? Colors.white60
                                      : Colors.black45,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  localization.addressDetails ??
                                      'Address Details',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDarkMode
                                        ? Colors.white60
                                        : Colors.black45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sellerInfo['address'] ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'IBAN',
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
                              _maskIban(sellerInfo['iban'] ?? ''),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.edit_rounded,
                              color: const Color(0xFF00A36C),
                              backgroundColor:
                                  const Color(0xFF00A36C).withOpacity(0.1),
                              onTap: () => _showSellerInfoModal(
                                context,
                                docRef,
                                sellerInfo: sellerInfo,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildActionButton(
                              icon: Icons.delete_outline_rounded,
                              color: Colors.red[400]!,
                              backgroundColor: Colors.red[50]!,
                              onTap: () =>
                                  _deleteSellerInfo(docRef, localization),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  String _maskIban(String iban) {
    if (iban.length <= 8) return iban;
    final start = iban.substring(0, 4);
    final end = iban.substring(iban.length - 4);
    return '$start••••••••$end';
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
    DocumentReference docRef,
    bool isDarkMode,
  ) {
    return Container(
      width: 240,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ElevatedButton(
        onPressed: () => _showSellerInfoModal(context, docRef),
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
              localization.addSellerInfo,
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

  void _showSellerInfoModal(
    BuildContext context,
    DocumentReference docRef, {
    Map<String, dynamic>? sellerInfo,
  }) {
    final parentContext = context;
    final localization = AppLocalizations.of(context);

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoSellerInfoFormModal(
          sellerInfo: sellerInfo,
          onSave: (Map<String, dynamic> sellerData) async {
            try {
              await docRef.update({'sellerInfo': sellerData});

              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text(sellerInfo == null
                        ? (localization.sellerInfoAdded ??
                            'Seller information added successfully')
                        : (localization.sellerInfoUpdated ??
                            'Seller information updated successfully')),
                    backgroundColor: const Color(0xFF00A86B),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${localization.errorOccurred ?? 'An error occurred'}: $e'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  Future<void> _deleteSellerInfo(
      DocumentReference docRef, AppLocalizations localization) async {
    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title:
            Text(localization.deleteSellerInfo ?? 'Delete Seller Information'),
        content: Text(localization.deleteSellerInfoConfirmation ??
            'Are you sure you want to delete your seller information?'),
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
        await docRef.update({'sellerInfo': null});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localization.sellerInfoDeleted ??
                  'Seller information deleted'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
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

class CupertinoSellerInfoFormModal extends StatefulWidget {
  final Map<String, dynamic>? sellerInfo;
  final Function(Map<String, dynamic>) onSave;

  const CupertinoSellerInfoFormModal({
    Key? key,
    this.sellerInfo,
    required this.onSave,
  }) : super(key: key);

  @override
  _CupertinoSellerInfoFormModalState createState() =>
      _CupertinoSellerInfoFormModalState();
}

class _CupertinoSellerInfoFormModalState
    extends State<CupertinoSellerInfoFormModal> {
  late TextEditingController _ibanOwnerNameController;
  late TextEditingController _ibanOwnerSurnameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _ibanController;
  LatLng? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _ibanOwnerNameController = TextEditingController(
      text: widget.sellerInfo?['ibanOwnerName'] ?? '',
    );
    _ibanOwnerSurnameController = TextEditingController(
      text: widget.sellerInfo?['ibanOwnerSurname'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.sellerInfo?['phone'] ?? '',
    );
    _addressController = TextEditingController(
      text: widget.sellerInfo?['address'] ?? '',
    );
    _ibanController = TextEditingController(
      text: widget.sellerInfo?['iban'] ?? '',
    );
    if (widget.sellerInfo != null &&
        widget.sellerInfo!['latitude'] != null &&
        widget.sellerInfo!['longitude'] != null) {
      _selectedLocation = LatLng(
        (widget.sellerInfo!['latitude'] as num).toDouble(),
        (widget.sellerInfo!['longitude'] as num).toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _ibanOwnerNameController.dispose();
    _ibanOwnerSurnameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  Future<void> _navigateToSelectLocation() async {
    final LatLng? result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => PinLocationScreen(
          initialLocation: _selectedLocation,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedLocation = result;
      });
    }
  }

  void _onSave() {
    final l10n = AppLocalizations.of(context);
    if (_ibanOwnerNameController.text.isEmpty ||
        _ibanOwnerSurnameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _selectedLocation == null ||
        _addressController.text.isEmpty ||
        _ibanController.text.isEmpty) {
      showCupertinoDialog(
        context: context,
        builder: (context) {
          return CupertinoAlertDialog(
            title: Text(l10n.error),
            content: Text(l10n.pleaseFillAllDetails),
            actions: [
              CupertinoDialogAction(
                child: Text(l10n.done),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          );
        },
      );
      return;
    }

    final sellerData = {
      'ibanOwnerName': _ibanOwnerNameController.text.trim(),
      'ibanOwnerSurname': _ibanOwnerSurnameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'latitude': _selectedLocation!.latitude,
      'longitude': _selectedLocation!.longitude,
      'address': _addressController.text.trim(),
      'iban': _ibanController.text.trim(),
    };

    Navigator.pop(context);
    widget.onSave(sellerData);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    final borderColor = Colors.grey[400]!;
    final placeholderStyle = TextStyle(
      color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? Colors.grey.shade700
                              : Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.sellerInfo == null
                          ? l10n.addSellerInfoTitle
                          : l10n.editSellerInfo,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Figtree',
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _ibanOwnerNameController,
                            placeholder: l10n.ibanOwnerName,
                            isDark: isDark,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            applyTitleCase: true,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _ibanOwnerSurnameController,
                            placeholder: l10n.ibanOwnerSurname,
                            isDark: isDark,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            applyTitleCase: true,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _phoneController,
                            placeholder: l10n.phoneNumber,
                            keyboardType: TextInputType.phone,
                            isDark: isDark,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _navigateToSelectLocation,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: borderColor, width: 1),
                                borderRadius: BorderRadius.circular(8),
                                color: isDark
                                    ? const Color.fromARGB(255, 45, 43, 61)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedLocation != null
                                          ? 'Lat: ${_selectedLocation!.latitude.toStringAsFixed(4)}, Lng: ${_selectedLocation!.longitude.toStringAsFixed(4)}'
                                          : l10n.pinLocationOnMap,
                                      style: TextStyle(
                                        color: _selectedLocation != null
                                            ? (isDark
                                                ? Colors.white
                                                : Colors.black)
                                            : (isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600]),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.location_on,
                                    color: _selectedLocation != null
                                        ? const Color(0xFF00A36C)
                                        : (isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600]),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _addressController,
                            placeholder: l10n.addressDetails,
                            isDark: isDark,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                            maxLines: 3,
                            applyTitleCase: true,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _ibanController,
                            placeholder: l10n.bankAccountNumberIban,
                            isDark: isDark,
                            borderColor: borderColor,
                            placeholderStyle: placeholderStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDark
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
                                l10n.cancel,
                                style: TextStyle(
                                  fontFamily: 'Figtree',
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoButton(
                              color: const Color(0xFF00A36C),
                              onPressed: _onSave,
                              child: Text(
                                l10n.save,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required bool isDark,
    required Color borderColor,
    required TextStyle placeholderStyle,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool applyTitleCase = false,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      maxLines: maxLines,
      padding: const EdgeInsets.all(12),
      inputFormatters: applyTitleCase ? [_TitleCaseFormatter()] : null,
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
}
