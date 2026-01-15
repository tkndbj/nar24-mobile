import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../utils/image_compression_utils.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import '../../models/product.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

class SellerPanelCollectionScreen extends StatefulWidget {
  const SellerPanelCollectionScreen({super.key});

  @override
  State<SellerPanelCollectionScreen> createState() =>
      _SellerPanelCollectionScreenState();
}

class _SellerPanelCollectionScreenState
    extends State<SellerPanelCollectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _collections = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final Set<BuildContext> _activeDialogs = {};

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Close all active dialogs
    for (final dialogContext in _activeDialogs) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    }
    _activeDialogs.clear();
    super.dispose();
  }

  Future<void> _loadCollections() async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;
    if (shopId == null) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final snapshot = await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .orderBy('createdAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _collections = snapshot.docs
              .map((doc) => {
                    'id': doc.id,
                    ...doc.data(),
                  })
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading collections: $e');
      if (mounted) {
        _showErrorSnackbar(AppLocalizations.of(context).loadCollectionsError);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showCreatingCollectionModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true, // ✅ CRITICAL: Use root navigator
      builder: (dialogContext) {
        _activeDialogs.add(dialogContext); // ✅ Track dialog
        return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color.fromARGB(255, 33, 31, 49)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1500),
                    builder: (context, value, child) {
                      return Transform.rotate(
                        angle: value * 2 * 3.14159,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [Colors.tealAccent, Colors.teal.shade300]
                                  : [Colors.teal, Colors.teal.shade600],
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(
                            Icons.collections_outlined,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.creatingCollection ?? 'Creating collection...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.pleaseWait ??
                        'Please wait while we create your collection',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 8,
                      width: double.infinity,
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.tealAccent : Colors.teal,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ));
      },
    ).then((_) {
      // ✅ ADD THIS: Remove when closed
      _activeDialogs.removeWhere((ctx) => !ctx.mounted);
    });
  }

  void _showDeletingCollectionModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true, // ✅ CRITICAL: Use root navigator
      builder: (dialogContext) {
        _activeDialogs.add(dialogContext); // ✅ Track dialog
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1500),
                  builder: (context, value, child) {
                    return Transform.rotate(
                      angle: value * 2 * 3.14159,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.red, Colors.redAccent],
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.deletingCollection ?? 'Deleting collection...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.pleaseWait ??
                      'Please wait while we delete your collection',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 8,
                    width: double.infinity,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 2),
                      builder: (context, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.transparent,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.red),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      // ✅ ADD THIS: Remove when closed
      _activeDialogs.removeWhere((ctx) => !ctx.mounted);
    });
  }

  void _showUpdatingProductsModal() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true, // ✅ CRITICAL: Use root navigator
      builder: (dialogContext) {
        _activeDialogs.add(dialogContext); // ✅ Track dialog
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1500),
                  builder: (context, value, child) {
                    return Transform.rotate(
                      angle: value * 2 * 3.14159,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.deepOrange],
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.sync,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.updatingProducts ?? 'Updating products...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.pleaseWait ??
                      'Please wait while we update the collection',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 8,
                    width: double.infinity,
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 2),
                      builder: (context, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.orange),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      // ✅ ADD THIS: Remove when closed
      _activeDialogs.removeWhere((ctx) => !ctx.mounted);
    });
  }

  Future<void> _createCollection(String name, {String? imageUrl}) async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;
    if (shopId == null) return;

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .add({
        'name': name,
        'imageUrl': imageUrl,
        'productIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadCollections();

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showSuccessSnackbar(
            AppLocalizations.of(context).collectionCreatedSuccess);
      }
    } catch (e) {
      debugPrint('Error creating collection: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showErrorSnackbar(AppLocalizations.of(context).collectionCreatedError);
      }
    }
  }

  Future<void> _updateCollectionDirectly(
      String collectionId, Map<String, dynamic> data) async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;
    if (shopId == null) return;

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .doc(collectionId)
          .update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadCollections();

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // Close the updating modal
        _showSuccessSnackbar(
            AppLocalizations.of(context).collectionUpdatedSuccess);
      }
    } catch (e) {
      debugPrint('Error updating collection: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // Close the updating modal
        _showErrorSnackbar(AppLocalizations.of(context).collectionUpdatedError);
      }
      rethrow;
    }
  }

  Future<void> _updateCollection(
      String collectionId, Map<String, dynamic> data) async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;
    if (shopId == null) return;

    if (mounted) {
      _showUpdatingProductsModal();
    }

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .doc(collectionId)
          .update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _loadCollections();

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showSuccessSnackbar(
            AppLocalizations.of(context).collectionUpdatedSuccess);
      }
    } catch (e) {
      debugPrint('Error updating collection: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showErrorSnackbar(AppLocalizations.of(context).collectionUpdatedError);
      }
      rethrow;
    }
  }

  Future<void> _deleteCollection(String collectionId) async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;
    if (shopId == null) return;

    if (mounted) {
      _showDeletingCollectionModal();
    }

    try {
      await _firestore
          .collection('shops')
          .doc(shopId)
          .collection('collections')
          .doc(collectionId)
          .delete();

      await _loadCollections();

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showSuccessSnackbar(
            AppLocalizations.of(context).collectionDeletedSuccess);
      }
    } catch (e) {
      debugPrint('Error deleting collection: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // ✅ Use root navigator
        _showErrorSnackbar(AppLocalizations.of(context).collectionDeletedError);
      }
    }
  }

  Future<String?> _uploadImage(XFile imageFile) async {
    if (!mounted) return null;

    final l10n = AppLocalizations.of(context);
    try {
      final provider = context.read<SellerPanelProvider>();
      final shopId = provider.selectedShop?.id;
      if (shopId == null) return null;

      // ✅ Step 1: Validate file type (only png, jpg, jpeg)
      final String fileName = imageFile.name.toLowerCase();
      final bool isValidType = fileName.endsWith('.png') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.heic') ||
          fileName.endsWith('.heif');

      if (!isValidType) {
        if (mounted) {
          _showErrorSnackbar(l10n.invalidImageFormat ??
              'Only PNG, JPG, and JPEG images are allowed');
        }
        return null;
      }

      // ✅ Step 2: Check file size (10MB limit)
      final fileSize = await imageFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        if (mounted) {
          _showErrorSnackbar(
              l10n.imageTooLarge ?? 'Image size must be less than 10MB');
        }
        return null;
      }

      // ✅ Step 3: Compress the image
      debugPrint(
          '🖼️ Original image size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      final File originalFile = File(imageFile.path);
      final File? compressedFile =
          await ImageCompressionUtils.ecommerceCompress(originalFile);

      if (compressedFile == null) {
        if (mounted) {
          _showErrorSnackbar(l10n.imageUploadError ??
              'Failed to compress image. Please try again.');
        }
        return null;
      }

      final compressedSize = await compressedFile.length();
      debugPrint(
          '✅ Compressed image size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint(
          '💾 Saved: ${((fileSize - compressedSize) / 1024 / 1024).toStringAsFixed(2)} MB');

      // ✅ Step 4: Upload to temporary location for moderation
      final tempFileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tempRef =
          _storage.ref().child('temp_moderation/$shopId/$tempFileName');

      await tempRef.putFile(compressedFile);
      final tempUrl = await tempRef.getDownloadURL();

      debugPrint('📤 Temporary image uploaded for moderation');

      // ✅ Step 5: Call Vision API for content moderation
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
            .httpsCallable('moderateImage');

        final result = await callable.call<Map<String, dynamic>>({
          'imageUrl': tempUrl,
        });

        final data = result.data;
        final approved = data['approved'] as bool? ?? false;
        final rejectionReason = data['rejectionReason'] as String?;

        if (!approved) {
          // ❌ Image rejected - delete temp file and show error
          await tempRef.delete();

          String errorMessage =
              l10n.imageRejected ?? 'Image contains inappropriate content';
          if (rejectionReason == 'adult_content') {
            errorMessage = l10n.adultContentError ??
                'Image contains explicit adult content';
          } else if (rejectionReason == 'violent_content') {
            errorMessage =
                l10n.violentContentError ?? 'Image contains violent content';
          }

          if (mounted) {
            _showErrorSnackbar(errorMessage);
          }

          debugPrint('❌ Image rejected: $rejectionReason');
          return null;
        }

        debugPrint('✅ Image approved by content moderation');
      } catch (e) {
        // If moderation fails, delete temp file and abort
        debugPrint('❌ Content moderation error: $e');
        await tempRef.delete();

        if (mounted) {
          _showErrorSnackbar(l10n.moderationError ??
              'Failed to verify image content. Please try again.');
        }
        return null;
      }

      // ✅ Step 6: Move approved image to permanent location
      final uploadFileName =
          'collection_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final finalRef =
          _storage.ref().child('collections/$shopId/$uploadFileName');

      // Copy from temp to final location
      final bytes = await compressedFile.readAsBytes();
      await finalRef.putData(bytes);
      final downloadUrl = await finalRef.getDownloadURL();

      // Delete temp file
      await tempRef.delete();

      debugPrint('🎉 Image uploaded successfully to permanent storage');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      if (mounted) {
        _showErrorSnackbar(l10n.imageUploadError ?? 'Failed to upload image');
      }
      return null;
    }
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showProductSelector(Map<String, dynamic> collection) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductSelectorSheet(
        collection: collection,
        onProductsUpdated: (productIds) async {
          // Create a safe update function that checks mounted state
          if (mounted) {
            await _updateCollection(
                collection['id'], {'productIds': productIds});
          }
        },
      ),
    );
  }

  // ... keeping all the dialog methods the same as they're working fine ...
  void _showCreateCollectionDialog() {
    final l10n = AppLocalizations.of(context);
    final TextEditingController controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    XFile? selectedImage;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: AnimatedPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                      // Title
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
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [
                                          Colors.tealAccent,
                                          Colors.teal.shade300
                                        ]
                                      : [Colors.teal, Colors.teal.shade600],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.collections_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.createCollection,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content area
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Image selector
                              GestureDetector(
                                onTap: () async {
                                  final XFile? image = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85, // ✅ Changed from 80
                                    maxWidth: 1200, // ✅ Added max dimensions
                                    maxHeight: 1200, // ✅ Added max dimensions
                                  );
                                  if (image != null) {
                                    // ✅ Additional validation
                                    final String fileName =
                                        image.name.toLowerCase();
                                    final bool isValid =
                                        fileName.endsWith('.png') ||
                                            fileName.endsWith('.webp') ||
                                            fileName.endsWith('.jpg') ||
                                            fileName.endsWith('.heic') ||
                                            fileName.endsWith('.heif') ||
                                            fileName.endsWith('.jpeg');

                                    if (isValid) {
                                      setState(() {
                                        selectedImage = image;
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(l10n
                                                  .invalidImageFormat ??
                                              'Only PNG, JPG, HEIC, HEIF and WEBP images are allowed'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Container(
                                  height: 100,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromARGB(255, 45, 43, 61)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[600]!
                                          : Colors.grey[300]!,
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  child: selectedImage != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            File(selectedImage!.path),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                              color: isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey.shade600,
                                              size: 32,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              l10n.coverImages,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Collection name input
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                  color: isDark
                                      ? const Color.fromARGB(255, 45, 43, 61)
                                      : Colors.grey.shade50,
                                ),
                                child: TextField(
                                  controller: controller,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: l10n.collectionName,
                                    hintStyle: TextStyle(
                                      color: isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[500],
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Helper text
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      (isDark ? Colors.tealAccent : Colors.teal)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: (isDark
                                            ? Colors.tealAccent
                                            : Colors.teal)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: isDark
                                          ? Colors.tealAccent
                                          : Colors.teal,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        l10n.collectionNameHelper ??
                                            'Choose a name that describes your collection',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.tealAccent
                                              : Colors.teal,
                                          fontWeight: FontWeight.w500,
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

                      // Bottom buttons
                      Container(
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
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CupertinoButton(
                                color: (controller.text.trim().isNotEmpty && selectedImage != null)
                                    ? (isDark ? Colors.tealAccent : Colors.teal)
                                    : CupertinoColors.inactiveGray,
                                onPressed: controller.text.trim().isNotEmpty
                                    ? () async {
                                        // Check if image is selected
                                        if (selectedImage == null) {
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.image_not_supported, color: Colors.white, size: 20),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: Text(l10n.pleaseSelectCoverImage ?? 'Please select a cover image')),
                                                ],
                                              ),
                                              backgroundColor: Colors.orange,
                                              behavior: SnackBarBehavior.floating,
                                              margin: const EdgeInsets.all(16),
                                            ),
                                          );
                                          return;
                                        }

                                        final name = controller.text.trim();
                                        Navigator.pop(context);

                                        // ✅ Show modal IMMEDIATELY
                                        _showCreatingCollectionModal();

                                        final imageUrl = await _uploadImage(selectedImage!);
                                        await _createCollection(name,
                                            imageUrl: imageUrl);
                                      }
                                    : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 18,
                                      color:
                                          isDark ? Colors.black : Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.create,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
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
            ),
          );
        },
      ),
    );
  }

  void _showEditCollectionDialog(Map<String, dynamic> collection) {
    final l10n = AppLocalizations.of(context);
    final TextEditingController controller =
        TextEditingController(text: collection['name']);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    XFile? selectedImage;
    String? currentImageUrl = collection['imageUrl'];

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: AnimatedPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                      // Title
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
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.orange.shade400,
                                    Colors.orange.shade600
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              l10n.editCollection,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content area
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Current collection info
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color.fromARGB(255, 45, 43, 61)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.collections_outlined,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${l10n.editing}: ${collection['name']}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Image selector
                              GestureDetector(
                                onTap: () async {
                                  final XFile? image = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85, // ✅ Changed from 80
                                    maxWidth: 1200, // ✅ Added max dimensions
                                    maxHeight: 1200, // ✅ Added max dimensions
                                  );
                                  if (image != null) {
                                    // ✅ Additional validation
                                    final String fileName =
                                        image.name.toLowerCase();
                                    final bool isValid =
                                        fileName.endsWith('.png') ||
                                            fileName.endsWith('.jpg') ||
                                            fileName.endsWith('.webp') ||
                                            fileName.endsWith('.heic') ||
                                            fileName.endsWith('.heif') ||
                                            fileName.endsWith('.jpeg');

                                    if (isValid) {
                                      setState(() {
                                        selectedImage = image;
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(l10n
                                                  .invalidImageFormat ??
                                              'Only PNG, JPG, and JPEG images are allowed'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Container(
                                  height: 100,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromARGB(255, 45, 43, 61)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[600]!
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: selectedImage != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            File(selectedImage!.path),
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : currentImageUrl != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.network(
                                                currentImageUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return _buildImagePlaceholder(
                                                      isDark);
                                                },
                                              ),
                                            )
                                          : _buildImagePlaceholder(isDark),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Collection name input
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                  color: isDark
                                      ? const Color.fromARGB(255, 45, 43, 61)
                                      : Colors.grey.shade50,
                                ),
                                child: TextField(
                                  controller: controller,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: l10n.collectionName,
                                    hintStyle: TextStyle(
                                      color: isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[500],
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom buttons
                      Container(
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
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: CupertinoButton(
                                color: controller.text.trim().isNotEmpty
                                    ? Colors.orange
                                    : CupertinoColors.inactiveGray,
                                onPressed: controller.text.trim().isNotEmpty
                                    ? () async {
                                        try {
                                          final name = controller.text.trim();

                                          // ✅ Show updating modal IMMEDIATELY
                                          _showUpdatingProductsModal();

                                          // ✅ Close the edit dialog
                                          Navigator.pop(context);

                                          Map<String, dynamic> updateData = {
                                            'name': name
                                          };

                                          // ✅ Handle image upload with proper error handling
                                          if (selectedImage != null) {
                                            final imageUrl = await _uploadImage(
                                                selectedImage!);

                                            if (imageUrl != null) {
                                              updateData['imageUrl'] = imageUrl;
                                            } else {
                                              // ❌ Upload failed - close the modal and return
                                              if (mounted) {
                                                Navigator.of(context,
                                                        rootNavigator: true)
                                                    .pop();
                                              }
                                              return;
                                            }
                                          }

                                          // ✅ Update collection
                                          await _updateCollectionDirectly(
                                              collection['id'], updateData);
                                        } catch (e) {
                                          // ✅ Catch any unexpected errors
                                          debugPrint(
                                              'Error in collection update: $e');
                                          if (mounted) {
                                            Navigator.of(context,
                                                    rootNavigator: true)
                                                .pop();
                                            _showErrorSnackbar(
                                                'Failed to update collection: $e');
                                          }
                                        }
                                      }
                                    : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.save_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.save,
                                      style: TextStyle(
                                        fontSize: 16,
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
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImagePlaceholder(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          color: isDark ? Colors.grey[400] : Colors.grey.shade600,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.coverImages,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[400] : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> collection) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
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
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.red.shade400, Colors.red.shade600],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.deleteCollection,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content area
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Collection info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collection['name'] ?? l10n.unnamedCollection,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.deleteCollectionConfirmation,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Warning message
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.deleteCollectionWarning ??
                                  'This action cannot be undone. Products will not be deleted.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade300,
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
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CupertinoButton(
                        color: Colors.red,
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteCollection(collection['id']);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.delete_forever_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.delete,
                              style: TextStyle(
                                fontSize: 16,
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1C1A29)
          : const Color.fromARGB(255, 244, 244, 244),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1C1A29) : Colors.white,
        title: Text(
          l10n.collections,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Info Section
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF2A2D3A), const Color(0xFF1F1F2E)]
                    : [Colors.teal.shade50, Colors.teal.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color:
                      isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.tealAccent.withOpacity(0.2)
                            : Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.collections_outlined,
                        color: isDark ? Colors.tealAccent : Colors.teal,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.manageCollections,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.collectionsDescription,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Create Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showCreateCollectionDialog,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: isDark ? Colors.tealAccent : Colors.teal,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: isDark ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.createCollection,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Collections List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _collections.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: _collections.length,
                        itemBuilder: (context, index) {
                          final collection = _collections[index];
                          return _buildCollectionCard(collection);
                        },
                      ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.collections_outlined,
            size: 80,
            color: isDark ? Colors.white30 : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noCollectionsYet,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.createFirstCollection,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.white30 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(Map<String, dynamic> collection) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final productIds = List<String>.from(collection['productIds'] ?? []);
    final imageUrl = collection['imageUrl'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Collection thumbnail
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.collections_outlined,
                                color: isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400,
                                size: 30,
                              );
                            },
                          )
                        : Icon(
                            Icons.collections_outlined,
                            color:
                                isDark ? Colors.white30 : Colors.grey.shade400,
                            size: 30,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection['name'] ?? l10n.unnamedCollection,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${productIds.length} ${l10n.products}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    size: 20,
                  ),
                  onPressed: () => _showEditCollectionDialog(collection),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.red.shade400,
                    size: 20,
                  ),
                  onPressed: () => _showDeleteConfirmation(collection),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _showProductSelector(collection),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: isDark
                      ? Colors.tealAccent.withOpacity(0.1)
                      : Colors.teal.withOpacity(0.1),
                  foregroundColor: isDark ? Colors.tealAccent : Colors.teal,
                  side: BorderSide(
                    color: isDark ? Colors.tealAccent : Colors.teal,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 18,
                      color: isDark ? Colors.tealAccent : Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.addProducts,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.tealAccent : Colors.teal,
                      ),
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
}

class ProductSelectorSheet extends StatefulWidget {
  final Map<String, dynamic> collection;
  final Function(List<String>) onProductsUpdated;

  const ProductSelectorSheet({
    super.key,
    required this.collection,
    required this.onProductsUpdated,
  });

  @override
  State<ProductSelectorSheet> createState() => _ProductSelectorSheetState();
}

class _ProductSelectorSheetState extends State<ProductSelectorSheet> {
  final ValueNotifier<Set<String>> selectedProductIdsNotifier =
      ValueNotifier({});
  final ValueNotifier<String> searchQueryNotifier = ValueNotifier('');
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(true);
  final ValueNotifier<bool> isLoadingMoreNotifier = ValueNotifier(false);

  List<Product> availableProducts = [];
  final TextEditingController searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  bool _isUpdating = false;

  // Pagination state
  static const int _pageSize = 20;
  static const int _maxProducts = 50;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    selectedProductIdsNotifier.value =
        Set<String>.from(widget.collection['productIds'] ?? []);
    _loadProducts();
    _setupScrollListener();

    searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          searchQueryNotifier.value = searchController.text;
        }
      });
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        // Only load more if not searching (search is client-side on loaded data)
        if (!isLoadingMoreNotifier.value &&
            _hasMore &&
            searchQueryNotifier.value.isEmpty) {
          _loadMoreProducts();
        }
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    searchController.dispose();
    _scrollController.dispose();
    selectedProductIdsNotifier.dispose();
    searchQueryNotifier.dispose();
    isLoadingNotifier.dispose();
    isLoadingMoreNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;

    if (shopId == null) {
      isLoadingNotifier.value = false;
      return;
    }

    try {
      final query = FirebaseFirestore.instance
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);

      final snapshot = await query.get();

      if (mounted) {
        availableProducts =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;

        isLoadingNotifier.value = false;
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) {
        isLoadingNotifier.value = false;
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    if (!mounted ||
        _lastDoc == null ||
        !_hasMore ||
        isLoadingMoreNotifier.value) return;

    final provider = context.read<SellerPanelProvider>();
    final shopId = provider.selectedShop?.id;

    if (shopId == null) return;

    isLoadingMoreNotifier.value = true;

    try {
      final query = FirebaseFirestore.instance
          .collection('shop_products')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize);

      final snapshot = await query.get();

      if (mounted) {
        final newProducts =
            snapshot.docs.map((doc) => Product.fromDocument(doc)).toList();

        availableProducts.addAll(newProducts);

        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == _pageSize;

        // Trigger rebuild by updating a notifier
        searchQueryNotifier.value = searchQueryNotifier.value;

        isLoadingMoreNotifier.value = false;
      }
    } catch (e) {
      debugPrint('Error loading more products: $e');
      if (mounted) {
        isLoadingMoreNotifier.value = false;
      }
    }
  }

  List<Product> _getFilteredProducts(String query) {
    if (query.isEmpty) return availableProducts;

    return availableProducts.where((product) {
      return product.productName.toLowerCase().contains(query.toLowerCase()) ||
          (product.brandModel ?? '')
              .toLowerCase()
              .contains(query.toLowerCase());
    }).toList();
  }

  // Helper method to build selected products text with proper localization
  String _buildSelectedProductsText(int count, AppLocalizations l10n) {
    try {
      // Try to call productsSelected as a function if it exists
      return (l10n.productsSelected as Function)(count).toString();
    } catch (e) {
      // Fallback if localization fails
      return count == 1
          ? '$count product selected'
          : '$count products selected';
    }
  }

  // Add this method to handle done button with debouncing
  Future<void> _handleDonePressed() async {
    if (_isUpdating || !mounted) return;

    final selectedIds = selectedProductIdsNotifier.value; // ✅ Get from notifier
    final originalProductIds =
        Set<String>.from(widget.collection['productIds'] ?? []);

    if (selectedIds.length == originalProductIds.length &&
        selectedIds.every((id) => originalProductIds.contains(id))) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await widget
          .onProductsUpdated(selectedIds.toList()); // ✅ Use from notifier
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error updating products: $e');
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update products. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatPrice(num price) {
    double rounded = double.parse(price.toStringAsFixed(2));
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1A29)
            : const Color.fromARGB(255, 244, 244, 244),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white30 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.selectProducts} - ${widget.collection['name']}',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                _isUpdating
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        onPressed: _handleDonePressed,
                        child: Text(
                          l10n.done,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.tealAccent : Colors.teal,
                          ),
                        ),
                      ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: searchController,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchProducts,
                hintStyle: GoogleFonts.inter(
                  color: isDark ? Colors.white30 : Colors.grey.shade500,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.white30 : Colors.grey.shade500,
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2D3A) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Selected Count - ✅ Using ValueListenableBuilder
          ValueListenableBuilder<Set<String>>(
            valueListenable: selectedProductIdsNotifier,
            builder: (context, selectedIds, child) {
              final isAtLimit = selectedIds.length >= _maxProducts;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAtLimit
                        ? Colors.orange.withOpacity(0.1)
                        : isDark
                            ? Colors.tealAccent.withOpacity(0.1)
                            : Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAtLimit
                          ? Colors.orange
                          : isDark
                              ? Colors.tealAccent
                              : Colors.teal,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${selectedIds.length}/$_maxProducts ${l10n.productsSelectedCount}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isAtLimit
                          ? Colors.orange
                          : isDark
                              ? Colors.tealAccent
                              : Colors.teal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),

          // Products List - ✅ Using ValueListenableBuilder
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: isLoadingNotifier,
              builder: (context, isLoading, child) {
                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ValueListenableBuilder<String>(
                  valueListenable: searchQueryNotifier,
                  builder: (context, searchQuery, child) {
                    final filtered = _getFilteredProducts(searchQuery);

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          searchQuery.isNotEmpty
                              ? l10n.noProductsFound
                              : l10n.noProductsAvailable,
                          style: GoogleFonts.inter(
                            color:
                                isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                      );
                    }

                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: selectedProductIdsNotifier,
                      builder: (context, selectedIds, child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: isLoadingMoreNotifier,
                          builder: (context, isLoadingMore, _) {
                            // Show loading indicator only when not searching
                            final showLoadingIndicator =
                                isLoadingMore && searchQuery.isEmpty;
                            final itemCount = filtered.length +
                                (showLoadingIndicator ? 1 : 0);

                            return ListView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: itemCount,
                              itemBuilder: (context, index) {
                                // Loading indicator at the end
                                if (index == filtered.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            isDark
                                                ? Colors.tealAccent
                                                : Colors.teal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final product = filtered[index];
                                final isSelected =
                                    selectedIds.contains(product.id);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color.fromARGB(255, 33, 31, 49)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: isDark
                                                ? Colors.tealAccent
                                                : Colors.teal,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: ListTile(
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: product.imageUrls.isNotEmpty
                                          ? Image.network(
                                              product.imageUrls.first,
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return Container(
                                                  width: 50,
                                                  height: 50,
                                                  color: isDark
                                                      ? Colors.grey.shade700
                                                      : Colors.grey.shade200,
                                                  child: Icon(
                                                    Icons.image_not_supported,
                                                    color: isDark
                                                        ? Colors.white30
                                                        : Colors.grey.shade400,
                                                  ),
                                                );
                                              },
                                            )
                                          : Container(
                                              width: 50,
                                              height: 50,
                                              color: isDark
                                                  ? Colors.grey.shade700
                                                  : Colors.grey.shade200,
                                              child: Icon(
                                                Icons.image,
                                                color: isDark
                                                    ? Colors.white30
                                                    : Colors.grey.shade400,
                                              ),
                                            ),
                                    ),
                                    title: Text(
                                      product.productName,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${_formatPrice(product.price)} ${product.currency}',
                                      style: GoogleFonts.inter(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: Checkbox(
                                      value: isSelected,
                                      onChanged: (value) {
                                        final newSet =
                                            Set<String>.from(selectedIds);
                                        if (value == true) {
                                          if (newSet.length >= _maxProducts) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  l10n.collectionProductLimitReached ??
                                                      'Maximum $_maxProducts products per collection',
                                                ),
                                                backgroundColor: Colors.orange,
                                                behavior:
                                                    SnackBarBehavior.floating,
                                              ),
                                            );
                                            return;
                                          }
                                          newSet.add(product.id);
                                        } else {
                                          newSet.remove(product.id);
                                        }
                                        selectedProductIdsNotifier.value =
                                            newSet;
                                      },
                                      activeColor: isDark
                                          ? Colors.tealAccent
                                          : Colors.teal,
                                    ),
                                    onTap: () {
                                      final newSet =
                                          Set<String>.from(selectedIds);
                                      if (isSelected) {
                                        newSet.remove(product.id);
                                      } else {
                                        if (newSet.length >= _maxProducts) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l10n.collectionProductLimitReached ??
                                                    'Maximum $_maxProducts products per collection',
                                              ),
                                              backgroundColor: Colors.orange,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        newSet.add(product.id);
                                      }
                                      selectedProductIdsNotifier.value = newSet;
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
