// lib/models/review_dialog_view_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:io';
import '../utils/image_compression_utils.dart';
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';

class ReviewDialogViewModel {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;
  
  double rating = 0;
  String reviewText = '';
  List<File> selectedImages = [];
  final String? orderId;

  // ✅ Add constants for validation
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedExtensions = ['.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp'];

  ReviewDialogViewModel({
    required this.firestore,
    required this.auth,
    required this.storage,
    this.orderId,
  });

  /// Validate file before processing
  Map<String, dynamic> _validateFile(File file, BuildContext context) {
    final l10n = AppLocalizations.of(context);
    try {
      // 1. Check file size
      final fileSize = file.lengthSync();
      if (fileSize > maxFileSizeBytes) {
        return {
          'valid': false,
          'error': 'file_too_large',
          'message': l10n.imageTooLarge,
        };
      }

      // 2. Check file extension
      final fileName = file.path.toLowerCase();
      final hasValidExtension = allowedExtensions.any((ext) => fileName.endsWith(ext));
      
      if (!hasValidExtension) {
        return {
          'valid': false,
          'error': 'invalid_format',
          'message': l10n.invalidImageFormat,
        };
      }

      return {'valid': true};
    } catch (e) {
      return {
        'valid': false,
        'error': 'validation_error',
        'message': l10n.moderationError,
      };
    }
  }

  Future<Map<String, dynamic>> _processImage(
    File imageFile, 
    String storagePath, 
    int index,
    BuildContext context
  ) async {
    try {
      // 1. Validate file first
      final validation = _validateFile(imageFile, context);
      if (validation['valid'] != true) {
        return {
          'success': false,
          'error': validation['error'],
          'message': validation['message'],
        };
      }

      // 2. Compress
      final compressedFile = await ImageCompressionUtils.simpleCompress(imageFile);
      final fileToUpload = compressedFile ?? imageFile;

      // 3. Upload to final location
      final fname = '${auth.currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}_${index}.jpg';
      final ref = storage.ref().child('$storagePath/$fname');
      
      await ref.putFile(fileToUpload);
      final imageUrl = await ref.getDownloadURL();

      // 4. Moderate
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('moderateImage');
      
      final result = await callable.call({'imageUrl': imageUrl});
      final data = result.data as Map<String, dynamic>;

      if (data['approved'] == true) {
        // Approved - keep it
        return {
          'success': true,
          'url': imageUrl,
          'ref': ref,
        };
      } else {
        // Rejected - delete it
        await ref.delete();
        return {
          'success': false,
          'error': data['rejectionReason'] ?? 'inappropriate_content',
        };
      }
    } catch (e) {
      print('Error processing image: $e');
      return {
        'success': false,
        'error': 'processing_error',
      };
    }
  }

  Future<void> submitReview({
    required String collectionPath,
    required String docId,
    required bool isProduct,
    required bool isShopProduct,
    required String? productId,
    required String? shopId,
    required String sellerId,
    required String storagePath,
    required String transactionId,
    required String orderId,
    required void Function() onSuccess,
    required void Function(String) onError,
    required BuildContext context,
  }) async {
    if (rating == 0 || reviewText.isEmpty) {
      onError('Please provide a rating and review text');
      return;
    }

    try {
      List<String> approvedUrls = [];
      List<Reference> uploadedRefs = [];
      
      if (isProduct && selectedImages.isNotEmpty) {
        for (int i = 0; i < selectedImages.length; i++) {
          final result = await _processImage(selectedImages[i], storagePath, i, context);
          
          if (!result['success']) {
            // Clean up previously uploaded images
            for (final ref in uploadedRefs) {
              try { await ref.delete(); } catch (_) {}
            }
            
            final error = result['error'] as String;
            String message = 'Image ${i + 1}: ';
            
            // ✅ Handle new validation errors
            if (result.containsKey('message')) {
              message += result['message'];
            } else {
              switch (error) {
                case 'adult_content': 
                  message += 'Contains inappropriate adult content'; 
                  break;
                case 'violent_content': 
                  message += 'Contains violent content'; 
                  break;
                case 'file_too_large':
                  message += 'File too large (max 10MB)';
                  break;
                case 'invalid_format':
                  message += 'Invalid format (JPG, PNG, HEIC only)';
                  break;
                case 'processing_error': 
                  message += 'Failed to process image'; 
                  break;
                default: 
                  message += 'Inappropriate content detected';
              }
            }
            
            onError(message);
            return;
          }
          
          approvedUrls.add(result['url'] as String);
          uploadedRefs.add(result['ref'] as Reference);
        }
      }

      final functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final callable = functions.httpsCallable('submitReview');

      final result = await callable.call(<String, dynamic>{
        'isProduct': isProduct,
        'isShopProduct': isShopProduct,
        'productId': productId,
        'sellerId': sellerId,
        'shopId': shopId,
        'transactionId': transactionId,
        'orderId': orderId,
        'rating': rating,
        'review': reviewText,
        'imageUrls': approvedUrls,
      });

      if ((result.data as Map)['success'] == true) {
        onSuccess();
      } else {
        onError('Unknown error submitting review');
      }
    } on FirebaseFunctionsException catch (e) {
      onError(e.message ?? 'Server error (${e.code})');
    } catch (e) {
      onError('An unexpected error occurred');
    }
  }
}