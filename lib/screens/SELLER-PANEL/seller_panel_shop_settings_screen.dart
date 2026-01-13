import 'dart:async';
import 'dart:io';
import '../../utils/image_compression_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:dotted_border/dotted_border.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/seller_panel_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SellerPanelShopSettingsScreen extends StatefulWidget {
  final String shopId;

  const SellerPanelShopSettingsScreen({
    Key? key,
    required this.shopId,
  }) : super(key: key);

  @override
  _SellerPanelShopSettingsScreenState createState() =>
      _SellerPanelShopSettingsScreenState();
}

class _SellerPanelShopSettingsScreenState
    extends State<SellerPanelShopSettingsScreen> {
  final ImagePicker _picker = ImagePicker();
  late final Future<void> _shopLoadFuture;

  @override
  void initState() {
    super.initState();
    _shopLoadFuture = _ensureShopSelected();
  }

  Future<void> _ensureShopSelected() async {
    final provider = Provider.of<SellerPanelProvider>(context, listen: false);
    final current = provider.selectedShop;
    if (current == null || current.id != widget.shopId) {
      await provider.switchShop(widget.shopId);
    }
  }

Future<void> _pickAndUpload({
  required String shopId,
  required String field,
  int? index,
}) async {
  try {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // Remove maxWidth, maxHeight, imageQuality since compression will handle optimization
    );
    if (picked == null) {
      return;  // User cancelled, don't show modal
    }

    // ✅ Show the animated modal IMMEDIATELY after image is picked
    if (mounted) {
      _showUploadingModal();
    }

    final file = File(picked.path);
    final fileSize = await file.length();
    final l10n = AppLocalizations.of(context);
    
    // Check if file is too large (10MB limit)
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception(l10n.imageTooLarge);
    }

    final ext = picked.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'].contains(ext)) {
      throw Exception(l10n.invalidImageFormat);
    }

    // Compress the image before uploading
    final compressedFile = await ImageCompressionUtils.ecommerceCompress(file);
    final fileToUpload = compressedFile ?? file;

    // ✅ Step 1: Upload to temporary location for moderation
    final tempFileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final tempRef = FirebaseStorage.instance
        .ref()
        .child('temp_moderation/$shopId/$tempFileName');

    await tempRef.putFile(
      fileToUpload,
      SettableMetadata(contentType: 'image/$ext'),
    );
    final tempUrl = await tempRef.getDownloadURL();
    
    debugPrint('📤 Temporary image uploaded for moderation');

    // ✅ Step 2: Call Vision API for content moderation
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
        
        String errorMessage = l10n.imageRejected ?? 'Image contains inappropriate content';
        if (rejectionReason == 'adult_content') {
          errorMessage = l10n.adultContentError ?? 'Image contains explicit adult content';
        } else if (rejectionReason == 'violent_content') {
          errorMessage = l10n.violentContentError ?? 'Image contains violent content';
        }
        
        throw Exception(errorMessage);
      }

      debugPrint('✅ Image approved by content moderation');
      
    } catch (e) {
      // If moderation fails, delete temp file and rethrow
      debugPrint('❌ Content moderation error: $e');
      await tempRef.delete();
      
      if (e is Exception && e.toString().contains('content')) {
        rethrow; // Rethrow content policy violations
      }
      
      throw Exception(l10n.moderationError ?? 
        'Failed to verify image content. Please try again.');
    }

    // ✅ Step 3: Get shop data and delete old images
    final shopRef = FirebaseFirestore.instance.collection('shops').doc(shopId);
    final doc = await shopRef.get();
    if (!doc.exists) {
      await tempRef.delete();
      throw Exception(l10n.shopNotFound);
    }
    final shopData = doc.data() as Map<String, dynamic>;

    // Delete old images from storage before uploading new ones
    if (field == 'profileImageUrl') {
      final String? oldUrl = shopData['profileImageUrl'] as String?;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(oldUrl).delete();
        } catch (_) {}
      }
    } else if (field == 'coverImageUrls') {
      final List<dynamic> covers = List.from(shopData['coverImageUrls'] ?? []);
      if (index != null && index < covers.length) {
        final String oldUrl = covers[index] as String;
        if (oldUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(oldUrl).delete();
          } catch (_) {}
        }
      }
    } else if (field == 'homeImageUrls') {
      final List<dynamic> homes = List.from(shopData['homeImageUrls'] ?? []);
      if (index != null && index < homes.length) {
        final String oldUrl = homes[index] as String;
        if (oldUrl.isNotEmpty) {
          try {
            await FirebaseStorage.instance.refFromURL(oldUrl).delete();
          } catch (_) {}
        }
      }
    }

    // ✅ Step 4: Move approved image to permanent location
    final String filename = index != null
        ? '${field}_$index'
        : '${field}_${DateTime.now().millisecondsSinceEpoch}';
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('shops/$shopId/$field/$filename.$ext');
    
    // Copy from temp to final location
    final bytes = await fileToUpload.readAsBytes();
    await storageRef.putData(
      bytes,
      SettableMetadata(contentType: 'image/$ext'),
    );
    final downloadUrl = await storageRef.getDownloadURL();
    
    // Delete temp file
    await tempRef.delete();
    
    debugPrint('🎉 Image uploaded successfully to permanent storage');

    // ✅ Step 5: Update Firestore with new image URL
    if (field == 'profileImageUrl') {
      await shopRef.update({'profileImageUrl': downloadUrl});
    } else if (field == 'coverImageUrls') {
      final List<dynamic> covers = List.from(shopData['coverImageUrls'] ?? []);
      if (index != null && index < covers.length) {
        covers[index] = downloadUrl;
      } else {
        covers.add(downloadUrl);
      }
      await shopRef.update({'coverImageUrls': covers});
    } else if (field == 'homeImageUrls') {
      final List<dynamic> homes = List.from(shopData['homeImageUrls'] ?? []);
      if (index != null && index < homes.length) {
        homes[index] = downloadUrl;
      } else {
        homes.add(downloadUrl);
      }
      await shopRef.update({'homeImageUrls': homes});
    }

    // ✅ Close the modal and show success
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close the uploading modal
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.imageUploadedSuccess ?? 'Image uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }

  } catch (e) {
    final l10n = AppLocalizations.of(context);
    String errorMessage;
    
    if (e.toString().contains('too large')) {
      errorMessage = l10n.imageTooLarge;
    } else if (e.toString().contains('IMAGE_TOO_LARGE')) {
      errorMessage = 'Image is too large. Please select images under 10MB.';
    } else if (e.toString().contains('adult content') || 
               e.toString().contains('violent content') ||
               e.toString().contains('inappropriate content')) {
      // Content moderation errors
      errorMessage = (e is Exception)
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
    } else {
      final msg = (e is Exception)
          ? e.toString().replaceFirst('Exception: ', '')
          : e.toString();
      errorMessage = msg;
    }
    
    // ✅ Close the modal before showing error
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close the uploading modal
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: (e.toString().contains('too large') || 
                           e.toString().contains('content')) 
              ? Colors.red 
              : null,
        ),
      );
    }
  }
}


  Future<void> _removeHomeImage(String imageUrl) async {
    final l10n = AppLocalizations.of(context);
    final shopRef =
        FirebaseFirestore.instance.collection('shops').doc(widget.shopId);
    final doc = await shopRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final List<dynamic> homes = List.from(data['homeImageUrls'] ?? []);
    final Map<String, dynamic> links =
        (data['homeImageLinks'] as Map?)?.cast<String, dynamic>() ?? {};

    try {
      final storageRef = FirebaseStorage.instance.refFromURL(imageUrl);
      await storageRef.delete();
    } catch (e) {
      debugPrint('Failed to delete home‐image from Storage: $e');
    }

    homes.remove(imageUrl);
    links.remove(imageUrl);

    await shopRef.update({
      'homeImageUrls': homes,
      'homeImageLinks': links,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.removedSuccessfully)),
    );
  }

  void _showUploadingModal() {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: Dialog(
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
              // Animated loading indicator
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Opacity(
                      opacity: 0.5 + (value * 0.5),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade400, Colors.blue.shade600],
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(
                          Icons.upload_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  );
                },
                onEnd: () {
                  // Restart animation if still mounted
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                l10n.uploadingImage ?? 'Uploading Image',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                l10n.pleaseWait ?? 'Please wait...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Loading bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Future<void> _unlinkHomeImage(String imageUrl) async {
    final l10n = AppLocalizations.of(context);
    final shopRef =
        FirebaseFirestore.instance.collection('shops').doc(widget.shopId);
    final doc = await shopRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final existingLinks =
        (data['homeImageLinks'] as Map?)?.cast<String, dynamic>() ?? {};

    if (existingLinks.containsKey(imageUrl)) {
      existingLinks.remove(imageUrl);
      await shopRef.update({'homeImageLinks': existingLinks});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.unlinkedSuccessfully)),
      );
    }
  }

  Future<void> _showProductSelectionModal(String imageUrl) async {
    final l10n = AppLocalizations.of(context);
    final shopProductsSnapshot = await FirebaseFirestore.instance
        .collection('shop_products')
        .where('shopId', isEqualTo: widget.shopId)
        .get();

    final products = shopProductsSnapshot.docs;

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noProductsToLink)),
      );
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: Text(l10n.selectProductToLink),
        actions: products.map((doc) {
          final data = doc.data();
          return CupertinoActionSheetAction(
            onPressed: () async {
              final selectedProductId = doc.id;
              final shopRef = FirebaseFirestore.instance
                  .collection('shops')
                  .doc(widget.shopId);
              final shopDoc = await shopRef.get();
              final shopData = shopDoc.data() ?? {};

              final existingLinks = (shopData['homeImageLinks'] as Map?)
                      ?.cast<String, dynamic>() ??
                  {};

              existingLinks[imageUrl] = selectedProductId;
              await shopRef.update({'homeImageLinks': existingLinks});

              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.linkedSuccessfully)),
              );
            },
            child: Text(data['productName'] as String? ?? doc.id),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          isDefaultAction: true,
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildDottedSquareNetwork({
    required String imageUrl,
    required VoidCallback onTap,
    required VoidCallback onEdit,
    required Color borderColor,
    double? fixedWidth,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorder(
        color: borderColor,
        strokeWidth: 2,
        dashPattern: const [6, 3],
        borderType: BorderType.RRect,
        radius: const Radius.circular(8),
        child: Container(
          width: fixedWidth ?? double.infinity,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, _) =>
                        Container(color: Colors.grey[300]),
                    errorWidget: (context, _, __) => Container(
                        color: Colors.grey[300], child: Icon(Icons.error)),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDottedSquareLocal({
    required XFile? imageFile,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    required Color borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorder(
        color: borderColor,
        strokeWidth: 2,
        dashPattern: const [6, 3],
        borderType: BorderType.RRect,
        radius: const Radius.circular(8),
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.transparent,
          ),
          child: imageFile != null
              ? Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(imageFile.path),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
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
                  size: 40,
                  color: borderColor,
                ),
        ),
      ),
    );
  }

  Widget _buildThumbnail({
    required String url,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8.0),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          color: Colors.grey[200],
        ),
        clipBehavior: Clip.hardEdge,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (_, __, ___) => const Icon(Icons.error),
        ),
      ),
    );
  }

  Widget _buildAddHomeImageButton() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDarkMode ? Colors.white : Colors.black;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _pickAndUpload(
          shopId: widget.shopId,
          field: 'homeImageUrls',
        ),
        child: DottedBorder(
          color: borderColor,
          strokeWidth: 2,
          dashPattern: const [6, 3],
          borderType: BorderType.RRect,
          radius: const Radius.circular(8),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.transparent,
            ),
            child: Center(
              child: Icon(
                Icons.add,
                size: 40,
                color: borderColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeImageItem(
    String url,
    Map<String, dynamic> homeLinks,
  ) {
    final l10n = AppLocalizations.of(context);
    final isLinked = homeLinks.containsKey(url);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (isLinked) {
                final linkedProductId = homeLinks[url] as String;
                context.push('/product_detail/$linkedProductId');
              }
            },
            child: DottedBorder(
              color: isDarkMode ? Colors.white : Colors.black,
              strokeWidth: 2,
              dashPattern: const [6, 3],
              borderType: BorderType.RRect,
              radius: const Radius.circular(8),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.transparent,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        placeholder: (context, _) =>
                            Container(color: Colors.grey[300]),
                        errorWidget: (context, _, __) => Container(
                            color: Colors.grey[300], child: Icon(Icons.error)),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _removeHomeImage(url),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isLinked
                ? Row(
                    children: [
                      Text(
                        l10n.linked,
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _unlinkHomeImage(url),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Checkbox(
                        value: false,
                        onChanged: (_) {
                          _showProductSelectionModal(url);
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          l10n.doYouWantToLinkToProduct,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<void>(
      future: _shopLoadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                l10n.shopSettings,
                style: GoogleFonts.figtree(
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
              foregroundColor: isDarkMode ? Colors.white : Colors.black,
              iconTheme: IconThemeData(
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              elevation: 2,
              shadowColor: Colors.black.withOpacity(0.4),
            ),
            body: Center(
              child: Text(
                '${l10n.initializationFailed}: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              l10n.shopSettings,
              style: GoogleFonts.figtree(
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            backgroundColor: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
            foregroundColor: isDarkMode ? Colors.white : Colors.black,
            iconTheme: IconThemeData(
              color: isDarkMode ? Colors.white : Colors.black,
            ),
            elevation: 2,
            shadowColor: Colors.black.withOpacity(0.4),
          ),
          body: SafeArea(
            top: false,
            child: Stack(
            children: [
              Container(
                  color: isDarkMode
                      ? const Color(0xFF1C1A29)
                      : const Color(0xFFF5F5F5),
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('shops')
                        .doc(widget.shopId)
                        .snapshots(),
                    builder: (context, shopSnapshot) {
                      if (!shopSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final data =
                          shopSnapshot.data!.data() as Map<String, dynamic>? ??
                              {};

                      final profileUrl =
                          data['profileImageUrl'] as String? ?? '';
                      final coverUrls =
                          (data['coverImageUrls'] as List?)?.cast<String>() ??
                              [];
                      final homeUrls =
                          (data['homeImageUrls'] as List?)?.cast<String>() ??
                              [];
                      final homeLinks = (data['homeImageLinks'] as Map?)
                              ?.cast<String, dynamic>() ??
                          {};

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(0.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Profile Image Section
                            _buildSectionTitle(l10n.profileImage),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1C1A29)
                                    : Colors.white,
                                borderRadius: BorderRadius.zero,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  if (profileUrl.isNotEmpty)
                                    _buildDottedSquareNetwork(
                                      imageUrl: profileUrl,
                                      borderColor: isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                      onTap: () => _pickAndUpload(
                                        shopId: widget.shopId,
                                        field: 'profileImageUrl',
                                      ),
                                      onEdit: () => _pickAndUpload(
                                        shopId: widget.shopId,
                                        field: 'profileImageUrl',
                                      ),
                                      fixedWidth: 100,
                                    )
                                  else
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: DottedBorder(
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black,
                                        strokeWidth: 2,
                                        dashPattern: const [6, 3],
                                        borderType: BorderType.RRect,
                                        radius: const Radius.circular(8),
                                        child: Container(
                                          width: 100,
                                          height: 100,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            color: Colors.transparent,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.add,
                                              size: 40,
                                              color: isDarkMode
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Cover Images Section
                            _buildSectionTitle(l10n.coverImages),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? const Color(0xFF1C1A29)
                                    : Colors.white,
                                borderRadius: BorderRadius.zero,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: SizedBox(
                                height: 100,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (int i = 0; i < coverUrls.length; i++)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4.0),
                                          child: _buildDottedSquareNetwork(
                                            imageUrl: coverUrls[i],
                                            borderColor: isDarkMode
                                                ? Colors.white
                                                : Colors.black,
                                            onTap: () => _pickAndUpload(
                                              shopId: widget.shopId,
                                              field: 'coverImageUrls',
                                              index: i,
                                            ),
                                            onEdit: () => _pickAndUpload(
                                              shopId: widget.shopId,
                                              field: 'coverImageUrls',
                                              index: i,
                                            ),
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0),
                                        child: DottedBorder(
                                          color: isDarkMode
                                              ? Colors.white
                                              : Colors.black,
                                          strokeWidth: 2,
                                          dashPattern: const [6, 3],
                                          borderType: BorderType.RRect,
                                          radius: const Radius.circular(8),
                                          child: GestureDetector(
                                            onTap: () => _pickAndUpload(
                                              shopId: widget.shopId,
                                              field: 'coverImageUrls',
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              height: 100,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                color: Colors.transparent,
                                              ),
                                              child: Center(
                                                child: Icon(
                                                  Icons.add,
                                                  size: 40,
                                                  color: isDarkMode
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Home Images Section
                            _buildSectionTitle(l10n.homeImages),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var url in homeUrls)
                                  Column(
                                    children: [
                                      _buildHomeImageItem(url, homeLinks),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? const Color(0xFF1C1A29)
                                        : Colors.white,
                                    borderRadius: BorderRadius.zero,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: _buildAddHomeImageButton(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      );
                    },
                  )),

            ],
          ),
          ),
        );
      },
    );
  }
}
