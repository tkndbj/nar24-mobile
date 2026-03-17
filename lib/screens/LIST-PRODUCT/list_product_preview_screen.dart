import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../constants/all_in_one_category_data.dart';
import '../../utils/attribute_localization_utils.dart';
import '../../utils/firebase_data_cleaner.dart';
import '../../utils/image_compression_utils.dart';
import '../../widgets/listproduct/upload_progress_state.dart';
import '../../widgets/listproduct/upload_progress_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal data class — a compressed file + its Storage destination metadata.
// ─────────────────────────────────────────────────────────────────────────────
class _UploadJob {
  final File file;
  final String folder;

  /// Non-null for color images; null for main images and video.
  final String? colorKey;

  /// True when this job carries the product video.
  final bool isVideo;

  const _UploadJob({
    required this.file,
    required this.folder,
    this.colorKey,
    this.isVideo = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Result produced by the upload pipeline, consumed by the CF / Firestore call.
// ─────────────────────────────────────────────────────────────────────────────
class _UploadResult {
  final List<String> imageUrls;
  final String? videoUrl;
  final Map<String, List<String>> colorImageUrls;

  const _UploadResult({
    required this.imageUrls,
    this.videoUrl,
    required this.colorImageUrls,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class ListProductPreviewScreen extends StatefulWidget {
  final Product product;
  final List<XFile> imageFiles;
  final XFile? videoFile;

  /// Raw color map from ListProductScreen — XFile images NOT yet uploaded.
  final Map<String, Map<String, dynamic>> selectedColorImages;

  final String phone;
  final String region;
  final String address;
  final String ibanOwnerName;
  final String ibanOwnerSurname;
  final String iban;
  final bool isEditMode;
  final Product? originalProduct;
  final bool isFromArchivedCollection;

  const ListProductPreviewScreen({
    Key? key,
    required this.product,
    required this.imageFiles,
    this.videoFile,
    required this.selectedColorImages,
    required this.phone,
    required this.region,
    required this.address,
    required this.ibanOwnerName,
    required this.ibanOwnerSurname,
    required this.iban,
    this.isEditMode = false,
    this.originalProduct,
    this.isFromArchivedCollection = false,
  }) : super(key: key);

  @override
  _ListProductPreviewScreenState createState() =>
      _ListProductPreviewScreenState();
}

class _ListProductPreviewScreenState extends State<ListProductPreviewScreen> {
  // ── Submission guards ─────────────────────────────────────────────
  /// Set synchronously on first tap — prevents any second call entering
  /// the pipeline before the first async frame even fires.
  bool _isSubmitting = false;

  /// Non-null while the upload + submit pipeline is running.
  /// Drives [UploadProgressOverlay]; null = overlay hidden.
  UploadState? _uploadState;

  // ── Firebase handles ──────────────────────────────────────────────
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// All active Storage subscriptions — cancelled on error or dispose so
  /// no callbacks fire after the widget is gone.
  final List<StreamSubscription<TaskSnapshot>> _storageSubs = [];

  @override
  void dispose() {
    for (final sub in _storageSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Small helpers
  // ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildDisplayAttributes() {
    final p = widget.product;
    return {
      if (p.clothingSizes != null) 'clothingSizes': p.clothingSizes,
      if (p.clothingFit != null) 'clothingFit': p.clothingFit,
      if (p.clothingTypes != null) 'clothingTypes': p.clothingTypes,
      if (p.pantSizes != null) 'pantSizes': p.pantSizes,
      if (p.pantFabricTypes != null) 'pantFabricTypes': p.pantFabricTypes,
      if (p.footwearSizes != null) 'footwearSizes': p.footwearSizes,
      if (p.jewelryMaterials != null) 'jewelryMaterials': p.jewelryMaterials,
      if (p.consoleBrand != null) 'consoleBrand': p.consoleBrand,
      if (p.curtainMaxWidth != null) 'curtainMaxWidth': p.curtainMaxWidth,
      if (p.curtainMaxHeight != null) 'curtainMaxHeight': p.curtainMaxHeight,
      ...p.attributes,
    };
  }

  /// Safe setState wrapper that also guards against post-dispose calls.
  void _setUploadState(UploadState state) {
    if (mounted) setState(() => _uploadState = state);
  }

  // ─────────────────────────────────────────────────────────────────
  // Upload pipeline
  //
  // Phase 1 — Compress all images (fast, offline, 0–15 % of bar)
  // Phase 2 — Measure compressed sizes → compute totalBytes
  // Phase 3 — Upload in batches of 3 with per-file Firebase progress
  //            events (15–95 % of bar)
  // Phase 4 — Caller switches to UploadPhase.submitting (95–100 %)
  // ─────────────────────────────────────────────────────────────────

 Future<_UploadResult> _uploadAllFiles(String userId) async {
  final mainFiles = widget.imageFiles.map((x) => File(x.path)).toList();
  final videoFile =
      widget.videoFile != null ? File(widget.videoFile!.path) : null;
  final colorEntries = <MapEntry<String, File>>[
    for (final entry in widget.selectedColorImages.entries)
      if (entry.value['image'] is XFile)
        MapEntry(entry.key, File((entry.value['image'] as XFile).path)),
  ];

  if (mainFiles.isEmpty && videoFile == null && colorEntries.isEmpty) {
    return _UploadResult(
      imageUrls: List<String>.from(widget.product.imageUrls),
      videoUrl: widget.product.videoUrl,
      colorImageUrls:
          Map<String, List<String>>.from(widget.product.colorImages),
    );
  }

  final jobs = <_UploadJob>[];

  // Main images — already compressed at pick time, add directly.
  for (final file in mainFiles) {
    jobs.add(_UploadJob(file: file, folder: 'default_images'));
  }

  // Video — no compression.
  if (videoFile != null) {
    jobs.add(_UploadJob(
      file: videoFile,
      folder: 'preview_videos',
      isVideo: true,
    ));
  }

  // Color images — compress silently here since they come from
  // a separate picker screen that doesn't compress on selection yet.
  for (final entry in colorEntries) {
    final compressed =
        await ImageCompressionUtils.ecommerceCompress(entry.value);
    jobs.add(_UploadJob(
      file: compressed ?? entry.value,
      folder: 'color_images/${entry.key}',
      colorKey: entry.key,
    ));
  }

  // ── Measure compressed sizes ───────────────────────────────────
  int totalBytes = 0;
  final fileSizes = <int>[];
  for (final job in jobs) {
    final size = await job.file.length();
    fileSizes.add(size);
    totalBytes += size;
  }

  // ── Upload ─────────────────────────────────────────────────────
  _setUploadState(UploadState(
    phase: UploadPhase.uploading,
    uploadedFiles: 0,
    totalFiles: jobs.length,
    bytesTransferred: 0,
    totalBytes: totalBytes,
  ));

  final bytesPerFile = List<int>.filled(jobs.length, 0);
  int completedFiles = 0;

  void onBytesUpdate(int idx, int bytes) {
    bytesPerFile[idx] = bytes;
    _setUploadState(_uploadState!.copyWith(
      bytesTransferred: bytesPerFile.fold<int>(0, (a, b) => a + b),
      uploadedFiles: completedFiles,
    ));
  }

  const maxConcurrent = 3;
  final uploadedUrls = List<String?>.filled(jobs.length, null);

  for (int start = 0; start < jobs.length; start += maxConcurrent) {
    final end = (start + maxConcurrent).clamp(0, jobs.length);

    await Future.wait(
      List.generate(end - start, (i) => start + i).map((globalIdx) async {
        uploadedUrls[globalIdx] = await _uploadFileWithRetry(
          file: jobs[globalIdx].file,
          userId: userId,
          folder: jobs[globalIdx].folder,
          fileIndex: globalIdx,
          onBytesUpdate: onBytesUpdate,
        );
        completedFiles++;
        bytesPerFile[globalIdx] = fileSizes[globalIdx];
        onBytesUpdate(globalIdx, fileSizes[globalIdx]);
      }),
    );
  }

  // ── Merge existing + newly uploaded URLs ──────────────────────
  final finalImageUrls = [
    ...widget.product.imageUrls,
    for (int i = 0; i < jobs.length; i++)
      if (!jobs[i].isVideo && jobs[i].colorKey == null) uploadedUrls[i]!,
  ];

  String? finalVideoUrl = widget.product.videoUrl;
  for (int i = 0; i < jobs.length; i++) {
    if (jobs[i].isVideo) {
      finalVideoUrl = uploadedUrls[i];
      break;
    }
  }

  final finalColorImages =
      Map<String, List<String>>.from(widget.product.colorImages);
  for (int i = 0; i < jobs.length; i++) {
    if (jobs[i].colorKey != null) {
      finalColorImages[jobs[i].colorKey!] = [uploadedUrls[i]!];
    }
  }

  return _UploadResult(
    imageUrls: finalImageUrls,
    videoUrl: finalVideoUrl,
    colorImageUrls: finalColorImages,
  );
}

  // ─────────────────────────────────────────────────────────────────
  // Single-file upload with Firebase Storage progress events
  // and exponential-backoff retry (up to 2 retries: 2 s, 4 s).
  // ─────────────────────────────────────────────────────────────────

  Future<String> _uploadFileWithRetry({
    required File file,
    required String userId,
    required String folder,
    required int fileIndex,
    required void Function(int fileIndex, int bytes) onBytesUpdate,
    int maxRetries = 2,
  }) async {
    int attempt = 0;

    while (true) {
      StreamSubscription<TaskSnapshot>? sub;
      try {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
        final ref =
            FirebaseStorage.instance.ref('products/$userId/$folder/$fileName');

        final task = ref.putFile(file);

        sub = task.snapshotEvents.listen(
          (snap) => onBytesUpdate(fileIndex, snap.bytesTransferred),
        );
        _storageSubs.add(sub);

        final snapshot = await task;
        sub.cancel();
        _storageSubs.remove(sub);

        return await snapshot.ref.getDownloadURL();
      } catch (e) {
        sub?.cancel();
        if (sub != null) _storageSubs.remove(sub);

        attempt++;
        if (attempt > maxRetries) rethrow;

        // Reset this file's progress before retrying.
        onBytesUpdate(fileIndex, 0);
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Submit — entry point called by the Confirm button
  // ─────────────────────────────────────────────────────────────────

  Future<void> _submitProduct() async {
    // Synchronous guard — blocks any second tap before the first await.
    if (_isSubmitting) return;
    _isSubmitting = true;

    // Count files so the initial compressing state is accurate.
    final newColorImageCount = widget.selectedColorImages.values
        .where((v) => v['image'] is XFile)
        .length;

   setState(() {
  _uploadState = UploadState(
    phase: UploadPhase.uploading,
    uploadedFiles: 0,
    totalFiles: widget.imageFiles.length + newColorImageCount,
    bytesTransferred: 0,
    totalBytes: 0,
  );
});

    try {
      final user = _auth.currentUser;
      if (user == null) {
        if (mounted) context.push('/login');
        return;
      }

      // Step 1 — Upload everything new, report progress.
      final upload = await _uploadAllFiles(user.uid);

      // Step 2 — Switch to "submitting" phase (CF / Firestore call).
      _setUploadState(UploadState(
        phase: UploadPhase.submitting,
        uploadedFiles: _uploadState?.totalFiles ?? 0,
        totalFiles: _uploadState?.totalFiles ?? 0,
        bytesTransferred: _uploadState?.totalBytes ?? 0,
        totalBytes: _uploadState?.totalBytes ?? 0,
      ));

      // Step 3 — Persist the product.
      if (widget.product.shopId != null) {
        await _submitViaCloudFunction(user, upload);
      } else {
        await _submitVitrinProduct(user, upload);
      }

      if (!mounted) return;
      context.go('/success');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final msg = switch (e.code) {
        'invalid-argument' => e.message ?? l10n.errorListingProduct,
        'permission-denied' => e.message ?? l10n.errorListingProduct,
        'unauthenticated' => l10n.pleaseLoginToContinue,
        'not-found' => e.message ?? l10n.errorListingProduct,
        _ => l10n.errorListingProduct,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).errorListingProduct)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _uploadState = null;
        });
      } else {
        _isSubmitting = false;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Cloud Function path (shop products)
  // ─────────────────────────────────────────────────────────────────

  Future<void> _submitViaCloudFunction(
    User user,
    _UploadResult upload,
  ) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
    final colorQuantities = widget.product.colorQuantities;
    final allColors = {
      ...upload.colorImageUrls.keys,
      ...colorQuantities.keys,
    }.toList();

    final payload = <String, dynamic>{
      'productName': widget.product.productName,
      'description': widget.product.description,
      'price': widget.product.price,
      'condition': widget.product.condition,
      'brandModel': widget.product.brandModel,
      'category': widget.product.category,
      'subcategory': widget.product.subcategory,
      'subsubcategory': widget.product.subsubcategory,
      'gender': widget.product.gender,
      'productType': widget.product.productType,
      'quantity': widget.product.quantity,
      'deliveryOption': widget.product.deliveryOption,
      'shopId': widget.product.shopId,
      'imageUrls': upload.imageUrls,
      'videoUrl': upload.videoUrl,
      'colorImages': upload.colorImageUrls,
      'colorQuantities': colorQuantities,
      'availableColors': allColors,
      if (widget.product.clothingSizes != null)
        'clothingSizes': widget.product.clothingSizes,
      if (widget.product.clothingFit != null)
        'clothingFit': widget.product.clothingFit,
      if (widget.product.clothingTypes != null)
        'clothingTypes': widget.product.clothingTypes,
      if (widget.product.pantSizes != null)
        'pantSizes': widget.product.pantSizes,
      if (widget.product.pantFabricTypes != null)
        'pantFabricTypes': widget.product.pantFabricTypes,
      if (widget.product.footwearSizes != null)
        'footwearSizes': widget.product.footwearSizes,
      if (widget.product.jewelryMaterials != null)
        'jewelryMaterials': widget.product.jewelryMaterials,
      if (widget.product.consoleBrand != null)
        'consoleBrand': widget.product.consoleBrand,
      if (widget.product.curtainMaxWidth != null)
        'curtainMaxWidth': widget.product.curtainMaxWidth,
      if (widget.product.curtainMaxHeight != null)
        'curtainMaxHeight': widget.product.curtainMaxHeight,
      'attributes': widget.product.attributes,
      'phone': widget.phone,
      'region': widget.region,
      'address': widget.address,
      'ibanOwnerName': widget.ibanOwnerName,
      'ibanOwnerSurname': widget.ibanOwnerSurname,
      'iban': widget.iban,
    };

    if (widget.isEditMode && widget.originalProduct != null) {
      final deletedColors = widget.originalProduct!.colorImages.keys
          .toSet()
          .difference(upload.colorImageUrls.keys.toSet())
          .toList();

      payload['originalProductId'] = widget.originalProduct!.id;
      payload['isArchivedEdit'] = widget.isFromArchivedCollection;
      payload['deletedColors'] = deletedColors;

      final result = await functions
          .httpsCallable('submitProductEdit')
          .call(payload);
      debugPrint('✅ Edit via CF: ${result.data['applicationId']}');
    } else {
      final result =
          await functions.httpsCallable('submitProduct').call(payload);
      debugPrint('✅ New product via CF: ${result.data['productId']}');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Vitrin (personal) path — direct Firestore write
  // ─────────────────────────────────────────────────────────────────

  Future<void> _submitVitrinProduct(
    User user,
    _UploadResult upload,
  ) async {
    final colorQuantities = widget.product.colorQuantities;
    final allColors = {
      ...upload.colorImageUrls.keys,
      ...colorQuantities.keys,
    }.toList();

    final deletedColors = widget.isEditMode && widget.originalProduct != null
        ? widget.originalProduct!.colorImages.keys
            .toSet()
            .difference(upload.colorImageUrls.keys.toSet())
            .toList()
        : <String>[];

    final productId =
        widget.isEditMode ? widget.originalProduct!.id : const Uuid().v4();

    final product = Product(
      id: productId,
      ownerId: user.uid,
      productName: widget.product.productName,
      description: widget.product.description,
      price: widget.product.price,
      condition: widget.product.condition,
      brandModel: widget.product.brandModel,
      currency: 'TL',
      gender: widget.product.gender,
      boostClickCountAtStart: widget.product.boostClickCountAtStart,
      imageUrls: upload.imageUrls,
      averageRating:
          widget.isEditMode ? widget.originalProduct!.averageRating : 0.0,
      reviewCount:
          widget.isEditMode ? widget.originalProduct!.reviewCount : 0,
      clickCount:
          widget.isEditMode ? widget.originalProduct!.clickCount : 0,
      favoritesCount:
          widget.isEditMode ? widget.originalProduct!.favoritesCount : 0,
      cartCount:
          widget.isEditMode ? widget.originalProduct!.cartCount : 0,
      purchaseCount:
          widget.isEditMode ? widget.originalProduct!.purchaseCount : 0,
      userId: user.uid,
      shopId: null,
      ilanNo: productId,
      createdAt: widget.isEditMode
          ? widget.originalProduct!.createdAt
          : Timestamp.now(),
      sellerName: widget.product.sellerName,
      category: widget.product.category,
      subcategory: widget.product.subcategory,
      subsubcategory: widget.product.subsubcategory,
      quantity: widget.product.quantity,
      deliveryOption: widget.product.deliveryOption,
      isFeatured:
          widget.isEditMode ? widget.originalProduct!.isFeatured : false,
      isBoosted:
          widget.isEditMode ? widget.originalProduct!.isBoosted : false,
      boostedImpressionCount: widget.isEditMode
          ? widget.originalProduct!.boostedImpressionCount
          : 0,
      boostImpressionCountAtStart: widget.isEditMode
          ? widget.originalProduct!.boostImpressionCountAtStart
          : 0,
      promotionScore:
          widget.isEditMode ? widget.originalProduct!.promotionScore : 0,
      paused: widget.isEditMode ? widget.originalProduct!.paused : false,
      boostStartTime: widget.isEditMode
          ? widget.originalProduct!.boostStartTime
          : null,
      boostEndTime:
          widget.isEditMode ? widget.originalProduct!.boostEndTime : null,
      lastClickDate: widget.isEditMode
          ? widget.originalProduct!.lastClickDate
          : null,
      clickCountAtStart: widget.isEditMode
          ? widget.originalProduct!.clickCountAtStart
          : 0,
      colorImages: upload.colorImageUrls,
      colorQuantities: colorQuantities,
      availableColors: allColors,
      videoUrl: upload.videoUrl,
      attributes: widget.product.attributes,
      productType: widget.product.productType,
      clothingSizes: widget.product.clothingSizes,
      clothingFit: widget.product.clothingFit,
      clothingTypes: widget.product.clothingTypes,
      pantSizes: widget.product.pantSizes,
      pantFabricTypes: widget.product.pantFabricTypes,
      footwearSizes: widget.product.footwearSizes,
      jewelryMaterials: widget.product.jewelryMaterials,
      consoleBrand: widget.product.consoleBrand,
      curtainMaxWidth: widget.product.curtainMaxWidth,
      curtainMaxHeight: widget.product.curtainMaxHeight,
      relatedProductIds: widget.isEditMode
          ? (widget.originalProduct!.relatedProductIds ?? [])
          : [],
      relatedLastUpdated: widget.isEditMode
          ? (widget.originalProduct!.relatedLastUpdated ??
              Timestamp.fromDate(DateTime(1970, 1, 1)))
          : Timestamp.fromDate(DateTime(1970, 1, 1)),
      relatedCount: widget.isEditMode
          ? (widget.originalProduct!.relatedCount ?? 0)
          : 0,
    );

    var productData = product.toMap();
    productData['phone'] = widget.phone;
    productData['region'] = widget.region;
    productData['address'] = widget.address;
    productData['ibanOwnerName'] = widget.ibanOwnerName;
    productData['ibanOwnerSurname'] = widget.ibanOwnerSurname;
    productData['iban'] = widget.iban;
    productData['campaign'] =
        widget.isEditMode ? (widget.originalProduct?.campaign ?? '') : '';
    productData['campaignName'] =
        widget.isEditMode ? (widget.originalProduct?.campaignName ?? '') : '';
    productData['updatedAt'] = FieldValue.serverTimestamp();
    productData = FirebaseDataCleaner.cleanData(productData);

    if (widget.isEditMode) {
      final detection = _detectChanges(widget.originalProduct!, product);
      final editedFields = detection['editedFields'] as List<String>;
      final changes = detection['changes'] as Map<String, dynamic>;

      if (deletedColors.isNotEmpty) {
        productData['deletedColors'] = deletedColors;
        if (!editedFields.contains('colorImages')) editedFields.add('colorImages');
        changes['colorImages'] ??= {
          'old': widget.originalProduct!.colorImages,
          'new': upload.colorImageUrls,
        };
      }

      productData['originalProductId'] = widget.originalProduct!.id;
      productData['originalProductData'] = FirebaseDataCleaner.cleanData(
          widget.originalProduct?.toMap() ?? {});
      productData['submittedAt'] = FieldValue.serverTimestamp();
      productData['status'] = 'pending';
      productData['editedFields'] = editedFields;
      productData['changes'] = changes;

      if (widget.isFromArchivedCollection) {
        productData['editType'] = 'archived_product_update';
        productData['sourceCollection'] = 'paused_shop_products';
        productData['needsUpdate'] = false;
        productData['archiveReason'] = null;
        productData['archivedByAdmin'] = false;
        productData['archivedByAdminAt'] = null;
        productData['archivedByAdminId'] = null;
        productData['paused'] = false;
      } else {
        productData['editType'] = 'product_edit';
        productData['sourceCollection'] = 'shop_products';
      }

      await _firestore
          .collection('vitrin_edit_product_applications')
          .doc(const Uuid().v4())
          .set(productData);
    } else {
      productData['status'] = 'pending';
      await _firestore
          .collection('vitrin_product_applications')
          .doc(productId)
          .set(productData);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Change detection (vitrin edit only)
  // ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _detectChanges(Product original, Product updated) {
    final editedFields = <String>[];
    final changes = <String, dynamic>{};

    dynamic normalize(dynamic v) {
      if (v == null || v == '' ||
          (v is List && v.isEmpty) ||
          (v is Map && v.isEmpty)) return null;
      return v;
    }

    void compare(String field, dynamic oldVal, dynamic newVal) {
      if (jsonEncode(normalize(oldVal)) != jsonEncode(normalize(newVal))) {
        editedFields.add(field);
        changes[field] = {'old': oldVal, 'new': newVal};
      }
    }

    compare('productName', original.productName, updated.productName);
    compare('description', original.description, updated.description);
    compare('price', original.price, updated.price);
    compare('condition', original.condition, updated.condition);
    compare('brandModel', original.brandModel, updated.brandModel);
    compare('category', original.category, updated.category);
    compare('subcategory', original.subcategory, updated.subcategory);
    compare('subsubcategory', original.subsubcategory, updated.subsubcategory);
    compare('gender', original.gender, updated.gender);
    compare('quantity', original.quantity, updated.quantity);
    compare('deliveryOption', original.deliveryOption, updated.deliveryOption);
    compare('imageUrls', original.imageUrls, updated.imageUrls);
    compare('videoUrl', original.videoUrl, updated.videoUrl);
    compare('colorImages', original.colorImages, updated.colorImages);
    compare('colorQuantities', original.colorQuantities, updated.colorQuantities);
    compare('productType', original.productType, updated.productType);
    compare('clothingSizes', original.clothingSizes, updated.clothingSizes);
    compare('clothingFit', original.clothingFit, updated.clothingFit);
    compare('clothingTypes', original.clothingTypes, updated.clothingTypes);
    compare('pantSizes', original.pantSizes, updated.pantSizes);
    compare('pantFabricTypes', original.pantFabricTypes, updated.pantFabricTypes);
    compare('footwearSizes', original.footwearSizes, updated.footwearSizes);
    compare('jewelryMaterials', original.jewelryMaterials, updated.jewelryMaterials);
    compare('consoleBrand', original.consoleBrand, updated.consoleBrand);
    compare('curtainMaxWidth', original.curtainMaxWidth, updated.curtainMaxWidth);
    compare('curtainMaxHeight', original.curtainMaxHeight, updated.curtainMaxHeight);

    return {'editedFields': editedFields, 'changes': changes};
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final localizedCategory = AllInOneCategoryData.localizeCategoryKey(
        widget.product.category, l10n);
    final localizedSubcategory = AllInOneCategoryData.localizeSubcategoryKey(
        widget.product.category, widget.product.subcategory, l10n);
    final localizedSubSub = widget.product.subsubcategory.isNotEmpty
        ? AllInOneCategoryData.localizeSubSubcategoryKey(
            widget.product.category,
            widget.product.subcategory,
            widget.product.subsubcategory,
            l10n)
        : null;

    final colorDisplay = widget.selectedColorImages.isNotEmpty
        ? widget.selectedColorImages.keys
            .map((c) => AttributeLocalizationUtils.localizeColorName(c, l10n))
            .join(', ')
        : null;

    // PopScope blocks the Android hardware back button while uploading.
    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isEditMode ? l10n.previewEditProduct : l10n.previewProduct,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
          ),
          iconTheme:
              IconThemeData(color: Theme.of(context).colorScheme.onSurface),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          automaticallyImplyLeading: !_isSubmitting,
        ),
        body: Stack(
          children: [
            // ── Scrollable preview content ─────────────────────────
            GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Container(
                color: isDark
                    ? const Color(0xFF1C1A29)
                    : const Color(0xFFF5F5F5),
                child: SafeArea(
                  bottom: true,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Product Details ────────────────────────
                        _sectionHeader(l10n.productDetails),
                        _card(
                          isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image grid
                              if (widget.imageFiles.isNotEmpty ||
                                  widget.product.imageUrls.isNotEmpty)
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 8.0,
                                  children: [
                                    ...widget.product.imageUrls
                                        .map(_networkThumb),
                                    ...widget.imageFiles
                                        .map((x) => _localThumb(x.path)),
                                  ],
                                ),
                              const SizedBox(height: 16),
                              _row(context, l10n.productTitle,
                                  widget.product.productName),
                              _row(context, l10n.category, localizedCategory),
                              _row(context, l10n.subcategory,
                                  localizedSubcategory),
                              _row(
                                  context,
                                  l10n.subSubcategory ?? 'Sub-subcategory',
                                  localizedSubSub ?? ''),
                              _row(context, l10n.brand,
                                  widget.product.brandModel ?? ''),
                              if (colorDisplay != null)
                                _row(context, l10n.color, colorDisplay),
                              _row(context, l10n.condition,
                                  widget.product.condition),
                              _row(context, l10n.price,
                                  '${widget.product.price}'),
                              _row(context, l10n.quantity,
                                  widget.product.quantity.toString()),
                              _row(context, l10n.description,
                                  widget.product.description),
                              // Dynamic attributes
                              ..._buildAttributeRows(context, l10n),
                              // Video
                              if (widget.videoFile != null) ...[
                                const SizedBox(height: 16),
                                Text(l10n.video,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                VideoPlayerWidget(
                                    file: File(widget.videoFile!.path)),
                              ],
                              // Color variant images
                              ..._buildColorRows(context, l10n, textTheme),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Seller Info ────────────────────────────
                        _sectionHeader(l10n.sellerInformation),
                        _card(
                          isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row(context, l10n.name,
                                  widget.product.sellerName),
                              _row(context, l10n.phoneNumber, widget.phone),
                              _row(context, l10n.region, widget.region),
                              _row(context, l10n.addressDetails, widget.address),
                              _row(context, l10n.bankAccountNumberIban,
                                  widget.iban),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Delivery ───────────────────────────────
                        _sectionHeader(l10n.deliveryOption),
                        _card(
                          isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: Image.asset(
                                      widget.product.deliveryOption ==
                                              'Self Delivery'
                                          ? 'assets/images/selfdelivery.png'
                                          : 'assets/images/fastdelivery.png',
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      widget.product.deliveryOption ==
                                              'Self Delivery'
                                          ? l10n.selfDelivery
                                          : l10n.fastDelivery,
                                      style: textTheme.bodyLarge?.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.product.deliveryOption == 'Self Delivery'
                                    ? l10n.selfDeliveryDescription
                                    : l10n.fastDeliveryDescription,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Stock Notice ───────────────────────────
                        _sectionHeader(l10n.stockInformation),
                        _card(
                          isDark,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Image.asset('assets/images/caution.png',
                                      width: 40, height: 40),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(l10n.stockInformation,
                                        style: textTheme.bodyLarge?.copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.stockInformationDescription,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Action Buttons ─────────────────────────
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _isSubmitting ? null : () => context.pop(),
                                  style: _buttonStyle(),
                                  child: Text(l10n.edit,
                                      style:
                                          const TextStyle(fontSize: 14)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _isSubmitting ? null : _submitProduct,
                                  style: _buttonStyle(),
                                  child: Text(
                                    widget.isEditMode
                                        ? l10n.submitEdit
                                        : l10n.confirmAndList,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Progress overlay (last in Stack = on top) ──────────
            if (_uploadState != null)
              UploadProgressOverlay(state: _uploadState!),
          ],
        ),
      ),
    );
  }

  // ── Attribute rows ────────────────────────────────────────────────

  List<Widget> _buildAttributeRows(
      BuildContext context, AppLocalizations l10n) {
    final attrs = _buildDisplayAttributes();
    if (attrs.isEmpty) return [];

    return [
      const SizedBox(height: 16),
      Text(l10n.details,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...attrs.entries.map((e) {
        try {
          final title = AttributeLocalizationUtils
              .getLocalizedAttributeTitle(e.key, l10n);
          final value = AttributeLocalizationUtils
              .getLocalizedAttributeValue(e.key, e.value, l10n);
          if (value.isEmpty) return const SizedBox.shrink();
          return _row(context, title, value);
        } catch (_) {
          final v = e.value is List
              ? (e.value as List).join(', ')
              : e.value.toString();
          if (v.isEmpty) return const SizedBox.shrink();
          return _row(context, e.key, v);
        }
      }),
    ];
  }

  List<Widget> _buildColorRows(
      BuildContext context, AppLocalizations l10n, TextTheme textTheme) {
    if (widget.selectedColorImages.isEmpty) return [];

    return [
      const SizedBox(height: 16),
      Text(l10n.colorImages,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...widget.selectedColorImages.entries.map((entry) {
        final color = entry.key;
        final imageData = entry.value['image'];
        final localizedColor =
            AttributeLocalizationUtils.localizeColorName(color, l10n);

        Widget? imageWidget;
        if (imageData is XFile) {
          imageWidget = _localThumb(imageData.path);
        } else if (imageData is String) {
          imageWidget = _networkThumb(imageData);
        } else if (widget.product.colorImages.containsKey(color)) {
          final urls = widget.product.colorImages[color]!;
          if (urls.isNotEmpty) imageWidget = _networkThumb(urls.first);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizedColor,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
              if (imageWidget != null) ...[
                const SizedBox(height: 8),
                imageWidget,
              ],
            ],
          ),
        );
      }),
    ];
  }

  // ── Reusable UI primitives ────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _card(bool isDark, {required Widget child}) => Container(
        width: double.infinity,
        color: isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.white,
        padding: const EdgeInsets.all(16.0),
        child: child,
      );

  Widget _row(BuildContext context, String title, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text('$title:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                    fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _networkThumb(String url) => ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.network(
          url,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : Container(
                  width: 100,
                  height: 100,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => Container(
            width: 100,
            height: 100,
            color: Colors.grey[300],
            child: const Icon(Icons.error, color: Colors.red),
          ),
        ),
      );

  Widget _localThumb(String path) => ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Image.file(File(path),
            width: 100, height: 100, fit: BoxFit.cover),
      );

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00A86B),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Video player (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class VideoPlayerWidget extends StatefulWidget {
  final File file;
  const VideoPlayerWidget({Key? key, required this.file}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller.setLooping(true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_controller),
                _ControlsOverlay(controller: _controller),
                VideoProgressIndicator(_controller, allowScrubbing: true),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class _ControlsOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  const _ControlsOverlay({Key? key, required this.controller})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          controller.value.isPlaying ? controller.pause() : controller.play(),
      child: controller.value.isPlaying
          ? const SizedBox.shrink()
          : Container(
              color: Colors.black54,
              child: const Center(
                child:
                    Icon(Icons.play_arrow, color: Colors.white, size: 60.0),
              ),
            ),
    );
  }
}