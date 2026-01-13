import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../utils/image_compression_utils.dart';
import '../AGREEMENTS/mesafeli_satis_sozlesmesi.dart';
import '../AGREEMENTS/satici_uyelik_ve_is_ortakligi.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../LOCATION-SCREENS/pin_location_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class CreateShopScreen extends StatefulWidget {
  const CreateShopScreen({Key? key}) : super(key: key);

  @override
  _CreateShopScreenState createState() => _CreateShopScreenState();
}

class _CreateShopScreenState extends State<CreateShopScreen> {
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactNoController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // FocusNodes for proper keyboard management
  final FocusNode _shopNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _contactNoFocus = FocusNode();
  final FocusNode _addressFocus = FocusNode();

  final ImagePicker _picker = ImagePicker();
  LatLng? _shopLocation;
  XFile? _profileImageFile;
  List<XFile?> _coverImageFiles = [null, null, null];
  XFile? _taxPlateCertificateFile;

  List<Map<String, String>> selectedCategories = [];
  bool _isSubmitting = false;

  final ValueNotifier<String> _uploadStatusNotifier = ValueNotifier('');
  final ValueNotifier<int> _uploadProgressNotifier = ValueNotifier(0);

  bool _isAgreementAccepted = false;
  int _totalUploads = 0;

  @override
  void dispose() {
    _shopNameController.dispose();
    _emailController.dispose();
    _contactNoController.dispose();
    _addressController.dispose();
    _shopNameFocus.dispose();
    _emailFocus.dispose();
    _contactNoFocus.dispose();
    _addressFocus.dispose();
    _uploadStatusNotifier.dispose();
    _uploadProgressNotifier.dispose();
    super.dispose();
  }

  /// Reliably dismisses the keyboard using multiple strategies
  Future<void> _dismissKeyboard() async {
    // Strategy 1: Unfocus any focused node
    FocusManager.instance.primaryFocus?.unfocus();

    // Strategy 2: Use system channel to hide keyboard explicitly
    await SystemChannels.textInput.invokeMethod('TextInput.hide');

    // Give the system time to process the dismissal
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<bool> _checkConnectivity() async {
  final connectivityResult = await Connectivity().checkConnectivity();
  return connectivityResult != ConnectivityResult.none;
}

// Add this method for retry logic
Future<T> _retryOperation<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 2),
}) async {
  int attempts = 0;
  while (true) {
    try {
      attempts++;
      return await operation();
    } catch (e) {
      if (attempts >= maxRetries) {
        rethrow;
      }
      // Only retry on network-related errors
      if (e.toString().contains('network') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        await Future.delayed(delay * attempts); // Exponential backoff
        continue;
      }
      rethrow;
    }
  }
}

  Future<bool> _validateImageFile(XFile file) async {
    final l10n = AppLocalizations.of(context);
    final File localFile = File(file.path);
    int fileSize = await localFile.length();

    // Check if file is too large (20MB limit)
    const int maxSizeInBytes = 20 * 1024 * 1024; // Changed from 30MB to 20MB
    if (fileSize > maxSizeInBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.imageTooLarge), // Use localized message
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    String ext = file.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.invalidFileType)),
      );
      return false;
    }
    return true;
  }

  String _getContentType(String path) {
    String ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _buildCombinedAgreementCheckbox() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.2)
              : Colors.black.withOpacity(0.1),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _isAgreementAccepted,
              onChanged: (value) {
                setState(() {
                  _isAgreementAccepted = value ?? false;
                });
              },
              activeColor: const Color(0xFF00A86B),
              checkColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Figtree',
                  color:
                      isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: l10n.iAgreeToThe ?? 'I agree to the '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SalesContractScreen(),
                          ),
                        );
                      },
                      child: Text(
                        l10n.mesafeliSatisSozlesmesi ??
                            'Distance Sales Agreement',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Figtree',
                          color: const Color(0xFF00A86B),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const SellerMembershipAndCooperationScreen(),
                          ),
                        );
                      },
                      child: Text(
                        l10n.saticiUyelikVeIsOrtakligi ??
                            'Seller Membership and Business Partnership Agreement',
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Figtree',
                          color: const Color(0xFF00A86B),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          height: 1.4,
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
    );
  }

  void _showFloatingSnackBar(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF00A86B),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);

    // Remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

 Future<void> _submitApplication() async {
  final l10n = AppLocalizations.of(context);

  // Validation
  if (_shopNameController.text.trim().isEmpty ||
      _emailController.text.trim().isEmpty ||
      _contactNoController.text.trim().isEmpty ||
      _addressController.text.trim().isEmpty ||
      selectedCategories.isEmpty ||
      _profileImageFile == null ||
      _taxPlateCertificateFile == null ||
      _isAgreementAccepted == false ||
      _shopLocation == null ||
      _coverImageFiles.every((file) => file == null)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.enterAllFields)),
    );
    return;
  }

  // Check connectivity before starting
  if (!await _checkConnectivity()) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.noInternetConnection ?? 'No internet connection. Please check your network and try again.'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: l10n.retry ?? 'Retry',
          textColor: Colors.white,
          onPressed: _submitApplication,
        ),
      ),
    );
    return;
  }

  // Prevent multiple submissions
  if (_isSubmitting) return;
  
  setState(() {
  _isSubmitting = true;  
  _totalUploads = 2 + _coverImageFiles.where((f) => f != null).length;
});

_uploadStatusNotifier.value = '';
_uploadProgressNotifier.value = 0;

  _showSubmittingModal();

  List<String> uploadedUrls = []; // Track for potential cleanup

  try {
    // Upload profile image
    _updateUploadStatus(l10n.uploadingProfileImage ?? 'Uploading profile image...');
    String profileImageUrl = await _retryOperation(() => _uploadFileToFirebase(
      File(_profileImageFile!.path),
      'profile_image',
    ));
    uploadedUrls.add(profileImageUrl);
    _incrementProgress();

    // Upload cover images
    List<String> coverImageUrls = [];
    for (int i = 0; i < _coverImageFiles.length; i++) {
      final file = _coverImageFiles[i];
      if (file != null) {
        _updateUploadStatus('${l10n.uploadingCoverImage ?? 'Uploading cover image'} ${i + 1}...');
        String url = await _retryOperation(() => _uploadFileToFirebase(
          File(file.path),
          'cover_image_$i',
        ));
        coverImageUrls.add(url);
        uploadedUrls.add(url);
        _incrementProgress();
      }
    }
    String coverImageUrl = coverImageUrls.join(',');

    // Upload tax certificate
    _updateUploadStatus(l10n.uploadingTaxCertificate ?? 'Uploading tax certificate...');
    String taxPlateCertificateUrl = await _retryOperation(() => _uploadFileToFirebase(
      File(_taxPlateCertificateFile!.path),
      'tax_plate_certificate',
    ));
    uploadedUrls.add(taxPlateCertificateUrl);
    _incrementProgress();

    // Save to Firestore
    _updateUploadStatus(l10n.savingApplication ?? 'Saving application...');
    await _retryOperation(() => _saveShopApplicationToFirestore(
      profileImageUrl: profileImageUrl,
      coverImageUrl: coverImageUrl,
      taxPlateCertificateUrl: taxPlateCertificateUrl,
    ));

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading modal

    _showFloatingSnackBar(l10n.shopApplicationSent);

    // Clear form
    _resetForm();
    
    Navigator.pop(context);
  } catch (e) {
    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading modal

    String errorMessage = _getErrorMessage(e, l10n);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: l10n.retry ?? 'Retry',
          textColor: Colors.white,
          onPressed: _submitApplication,
        ),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }
}

void _updateUploadStatus(String status) {
  _uploadStatusNotifier.value = status;
}

void _incrementProgress() {
  _uploadProgressNotifier.value++;
}

void _resetForm() {
  _shopNameController.clear();
  _emailController.clear();
  _contactNoController.clear();
  _addressController.clear();
  setState(() {
    _profileImageFile = null;
    _coverImageFiles = [null, null, null];
    _taxPlateCertificateFile = null;
    selectedCategories = [];
    _shopLocation = null;
  });
}

String _getErrorMessage(dynamic e, AppLocalizations l10n) {
  final errorStr = e.toString().toLowerCase();
  
  if (errorStr.contains('too large')) {
    return l10n.imageTooLarge;
  } else if (errorStr.contains('network') || 
             errorStr.contains('socket') || 
             errorStr.contains('timeout') ||
             errorStr.contains('failed host lookup')) {
    return l10n.networkError ?? 'Network error. Please check your connection and try again.';
  } else if (errorStr.contains('permission')) {
    return l10n.permissionDenied ?? 'Permission denied. Please try again.';
  } else if (errorStr.contains('not authenticated')) {
    return l10n.sessionExpired ?? 'Session expired. Please log in again.';
  }
  
  return '${l10n.errorSubmittingApplication} ${e.toString()}';
}

void _showSubmittingModal() {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00A86B), Color(0xFF00C574)],
                  ),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.submittingApplication,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Use ValueListenableBuilder for status
              ValueListenableBuilder<String>(
                valueListenable: _uploadStatusNotifier,
                builder: (context, status, child) {
                  return Text(
                    status.isNotEmpty 
                        ? status 
                        : l10n.pleaseWaitWhileWeProcessYourApplication,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 20),
              // Use ValueListenableBuilder for progress
              ValueListenableBuilder<int>(
                valueListenable: _uploadProgressNotifier,
                builder: (context, progress, child) {
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 8,
                          width: double.infinity,
                          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                          child: LinearProgressIndicator(
                            value: _totalUploads > 0 
                                ? progress / _totalUploads 
                                : null,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF00A86B),
                            ),
                          ),
                        ),
                      ),
                      if (_totalUploads > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '$progress / $_totalUploads',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Future<String> _uploadFileToFirebase(File file, String folder) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }

    try {
      // Compress the image before uploading
      final compressedFile =
          await ImageCompressionUtils.ecommerceCompress(file);
      final fileToUpload = compressedFile ?? file;

      String fileName =
          'shop_applications/${user.uid}/${folder}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);
      UploadTask uploadTask = storageRef.putFile(
        fileToUpload,
        SettableMetadata(contentType: _getContentType(fileToUpload.path)),
      );

      TaskSnapshot snapshot = await uploadTask.whenComplete(() => null);
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (e.toString().contains('too large')) {
        throw 'Image is too large. Please select images under 20MB.';
      }
      rethrow;
    }
  }

  Future<void> _saveShopApplicationToFirestore({
    required String profileImageUrl,
    required String coverImageUrl,
    required String taxPlateCertificateUrl,
  }) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'User not authenticated';
    }

    CollectionReference applicationsRef =
        FirebaseFirestore.instance.collection('shopApplications');

    await applicationsRef.add({
      'ownerId': user.uid,
      'name': _shopNameController.text.trim(),
      'email': _emailController.text.trim(), // ADD THIS LINE
      'contactNo': _contactNoController.text.trim(),
      'address': _addressController.text.trim(),
      'categories': selectedCategories.map((cat) => cat['code']).toList(),
      'profileImageUrl': profileImageUrl,
      'coverImageUrl': coverImageUrl,
      'taxPlateCertificateUrl': taxPlateCertificateUrl,
      'isAgreementAccepted': _isAgreementAccepted,
      'latitude': _shopLocation!.latitude, // ADD THIS LINE
      'longitude': _shopLocation!.longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Future<void> _navigateToPinLocation() async {
    // Dismiss keyboard before navigation
    await _dismissKeyboard();
    if (!mounted) return;

    final LatLng? result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => PinLocationScreen(
          initialLocation: _shopLocation,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _shopLocation = result;
      });
    }
  }

  /// Shows action sheet so user can pick or capture *profile* image.
  Future<void> _showProfileImageOptions() async {
    // Dismiss keyboard first and wait for it to complete
    await _dismissKeyboard();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    await showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? image =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (image != null && mounted && await _validateImageFile(image)) {
                if (!mounted) return;
                setState(() {
                  _profileImageFile = image;
                });
              }
            },
            child: Text(
              l10n.pickFromGallery,
              style: TextStyle(color: textColor),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? image =
                  await _picker.pickImage(source: ImageSource.camera);
              if (image != null && mounted && await _validateImageFile(image)) {
                if (!mounted) return;
                setState(() {
                  _profileImageFile = image;
                });
              }
            },
            child: Text(
              l10n.capturePhoto,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(
            l10n.cancel,
            style: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }

  /// Shows action sheet so user can pick or capture a *cover* image at [index].
  Future<void> _showCoverImageOptions(int index) async {
    // Dismiss keyboard first and wait for it to complete
    await _dismissKeyboard();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    await showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? image =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (image != null && mounted && await _validateImageFile(image)) {
                if (!mounted) return;
                setState(() {
                  _coverImageFiles[index] = image;
                });
              }
            },
            child: Text(
              l10n.pickFromGallery,
              style: TextStyle(color: textColor),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? image =
                  await _picker.pickImage(source: ImageSource.camera);
              if (image != null && mounted && await _validateImageFile(image)) {
                if (!mounted) return;
                setState(() {
                  _coverImageFiles[index] = image;
                });
              }
            },
            child: Text(
              l10n.capturePhoto,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(
            l10n.cancel,
            style: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }

  /// Shows action sheet so user can pick or capture *tax certificate* image.
  Future<void> _showTaxCertificateOptions() async {
    // Dismiss keyboard first and wait for it to complete
    await _dismissKeyboard();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black;

    await showCupertinoModalPopup(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? file =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (file != null && mounted && await _validateImageFile(file)) {
                if (!mounted) return;
                setState(() {
                  _taxPlateCertificateFile = file;
                });
              }
            },
            child: Text(
              l10n.pickFromGallery,
              style: TextStyle(color: textColor),
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              if (!mounted) return;

              final XFile? file =
                  await _picker.pickImage(source: ImageSource.camera);
              if (file != null && mounted && await _validateImageFile(file)) {
                if (!mounted) return;
                setState(() {
                  _taxPlateCertificateFile = file;
                });
              }
            },
            child: Text(
              l10n.capturePhoto,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(
            l10n.cancel,
            style: TextStyle(color: textColor),
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryPicker() async {
    // Dismiss keyboard first and wait for it to complete
    await _dismissKeyboard();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final categories = AllInOneCategoryData.kCategories
        .map((cat) => {
              'code': cat['key']!,
              'name':
                  AllInOneCategoryData.localizeCategoryKey(cat['key']!, l10n),
            })
        .toList();

    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            return CupertinoActionSheet(
              title: Text(
                l10n.selectCategory,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: categories.map((category) {
                bool isSelected = selectedCategories
                    .any((cat) => cat['code'] == category['code']);
                return CupertinoActionSheetAction(
                  onPressed: () {
                    modalSetState(() {
                      if (isSelected) {
                        selectedCategories.removeWhere(
                            (cat) => cat['code'] == category['code']);
                      } else {
                        selectedCategories.add(category);
                      }
                    });
                    setState(() {});
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        category['name']!,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Figtree',
                        ),
                      ),
                      if (isSelected) const SizedBox(width: 8),
                      if (isSelected)
                        Icon(
                          Icons.check,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                    ],
                  ),
                );
              }).toList(),
              cancelButton: CupertinoActionSheetAction(
                onPressed: () {
                  if (selectedCategories.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.selectAtLeastOneCategory)),
                    );
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  l10n.done,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSingleDottedImagePicker({
    required String title,
    required XFile? imageFile,
    required VoidCallback onTap,
    VoidCallback? onRemove,
    bool isCoverImage = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color boxColor = isDarkMode ? Colors.white : Colors.black;

    // Use the same fixed size for everything:
    const double squareSize = 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Container(
          width: isCoverImage ? squareSize : double.infinity,
          padding: isCoverImage ? EdgeInsets.zero : const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: isCoverImage
                ? Colors.transparent
                : (isDarkMode ? const Color(0xFF211F31) : Colors.white),
            borderRadius: BorderRadius.zero,
          ),
          child: Align(
            alignment: isCoverImage ? Alignment.center : Alignment.centerLeft,
            child: GestureDetector(
              // Keyboard dismissal is now handled in the onTap methods themselves
              onTap: onTap,
              child: DottedBorder(
                borderType: BorderType.RRect,
                radius: const Radius.circular(8),
                dashPattern: const [6, 3],
                color: boxColor,
                strokeWidth: 2,
                child: Container(
                  width: squareSize,
                  height: squareSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: imageFile != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(imageFile.path),
                                width: squareSize,
                                height: squareSize,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (onRemove != null)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: onRemove,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : Icon(
                          Icons.add,
                          size: squareSize * 0.4,
                          color: boxColor,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Get bottom padding for safe area (notch, home indicator, etc.)
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return PopScope(
      canPop: !_isSubmitting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSubmitting) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pleaseWaitSubmissionInProgress ??
                  'Please wait, submission in progress...'),
            ),
          );
        }
      },
      child: GestureDetector(
        // Dismiss keyboard when tapping outside of text fields
        onTap: () => _dismissKeyboard(),
        // Don't absorb pointer events - let child widgets handle their own taps
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          // Explicitly set to handle keyboard insets properly
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              l10n.createYourShop,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            iconTheme:
                IconThemeData(color: Theme.of(context).colorScheme.onSurface),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
          ),
          body: Stack(
            children: [
              Container(
                color: isDarkMode
                    ? const Color(0xFF1C1A29)
                    : const Color(0xFFF5F5F5),
                child: SingleChildScrollView(
                  // Key change: Use keyboardDismissBehavior to handle drag dismiss
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        color:
                            isDarkMode ? const Color(0xFF211F31) : Colors.white,
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/images/shopbubble.png',
                              width: 80,
                              height: 80,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                l10n.createAndNameYourShop,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.nameYourShop,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: _shopNameController,
                            focusNode: _shopNameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                FocusScope.of(context).requestFocus(_emailFocus),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: l10n.enterShopName,
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.email,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: _emailController,
                            focusNode: _emailFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_contactNoFocus),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: l10n.enterEmail,
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.contactNo,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: _contactNoController,
                            focusNode: _contactNoFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_addressFocus),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: l10n.enterContactNo,
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.shopAddress,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: _addressController,
                            focusNode: _addressFocus,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _dismissKeyboard(),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: l10n.enterAddress,
                              hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.pinLocationOnMap,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info text
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange.shade700,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.toOptimizeOrderDelivery,
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Pin location button
                            // Pin location button
Center(
  child: Container(
    width: 320,
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ElevatedButton(
      onPressed: _navigateToPinLocation,
      style: ElevatedButton.styleFrom(
        backgroundColor: _shopLocation == null
            ? const Color(0xFF00A86B)
            : Colors.green.shade600,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(320, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_on_rounded, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              _shopLocation == null
                  ? l10n.pinLocationOnMap
                  : 'Lat: ${_shopLocation!.latitude.toStringAsFixed(4)}, Lng: ${_shopLocation!.longitude.toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Figtree',
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  ),
),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.selectCategory,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showCategoryPicker,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF211F31)
                                : Colors.white,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedCategories.isEmpty
                                      ? l10n.selectCategory
                                      : selectedCategories
                                          .map((cat) => cat['name'])
                                          .join(', '),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: selectedCategories.isNotEmpty
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSingleDottedImagePicker(
                        title: l10n.taxPlateCertificate,
                        imageFile: _taxPlateCertificateFile,
                        onTap: _showTaxCertificateOptions,
                        onRemove: () {
                          setState(() {
                            _taxPlateCertificateFile = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildSingleDottedImagePicker(
                        title: l10n.uploadProfileImage,
                        imageFile: _profileImageFile,
                        onTap: _showProfileImageOptions,
                        onRemove: () {
                          setState(() {
                            _profileImageFile = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          l10n.uploadCoverImage,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF211F31)
                              : Colors.white,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildSingleDottedImagePicker(
                              title: '',
                              imageFile: _coverImageFiles[0],
                              onTap: () => _showCoverImageOptions(0),
                              onRemove: () {
                                setState(() {
                                  _coverImageFiles[0] = null;
                                });
                              },
                              isCoverImage: true,
                            ),
                            _buildSingleDottedImagePicker(
                              title: '',
                              imageFile: _coverImageFiles[1],
                              onTap: () => _showCoverImageOptions(1),
                              onRemove: () {
                                setState(() {
                                  _coverImageFiles[1] = null;
                                });
                              },
                              isCoverImage: true,
                            ),
                            _buildSingleDottedImagePicker(
                              title: '',
                              imageFile: _coverImageFiles[2],
                              onTap: () => _showCoverImageOptions(2),
                              onRemove: () {
                                setState(() {
                                  _coverImageFiles[2] = null;
                                });
                              },
                              isCoverImage: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCombinedAgreementCheckbox(),
                      const SizedBox(height: 24),
                      Center(
  child: Container(
    width: 320,
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: ElevatedButton(
      onPressed: _isSubmitting ? null : _submitApplication,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(240, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      child: _isSubmitting
          ? const CupertinoActivityIndicator(
              color: Colors.white,
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.send_rounded, size: 22),
                const SizedBox(width: 10),
                Text(
                  l10n.apply2,
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
  ),
),
                      // Add bottom padding to account for safe area (notch, home indicator)
                      SizedBox(height: 16 + bottomPadding),
                    ],
                  ),
                ),
              ),
              if (_isSubmitting)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CupertinoActivityIndicator(
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
