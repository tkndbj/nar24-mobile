import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressionUtils {
  // Compress image with optimal settings matching TypeScript version
  static Future<File?> compressImage(
    File file, {
    int quality = 90,
    int maxWidth = 1920,
    int maxHeight = 1920,
    CompressFormat format = CompressFormat.jpeg,
  }) async {
    try {
      // Get file info
      final fileSize = await file.length();
      print('Original file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // Skip compression if file is already small (less than 500KB)
      if (fileSize < 500 * 1024) {
        print('File is already small, skipping compression');
        return file;
      }

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_compressed.jpg',
      );

      // Compress with file method that supports more parameters
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: quality,
        minWidth: 300,
        minHeight: 300,
        format: format,
        keepExif: false,
      );

      if (compressedBytes != null) {
        // Write compressed bytes to file
        final compressedFile = File(targetPath);
        await compressedFile.writeAsBytes(compressedBytes);
        
        final compressedSize = compressedBytes.length;
        final compressionRatio = (1 - (compressedSize / fileSize)) * 100;
        
        print('Compressed file size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('Compression ratio: ${compressionRatio.toStringAsFixed(1)}%');
        
        return compressedFile;
      }

      return file; // Return original if compression failed
    } catch (e) {
      print('Error compressing image: $e');
      return file; // Return original file if compression fails
    }
  }

  // Alternative method with dimension control
  static Future<File?> compressImageWithDimensions(
    File file, {
    int quality = 90,
    int maxWidth = 1920,
    int maxHeight = 1920,
  }) async {
    try {
      final fileSize = await file.length();
      print('Original file size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      if (fileSize < 500 * 1024) {
        print('File is already small, skipping compression');
        return file;
      }

      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_compressed.jpg',
      );

      // Use compressAndGetFile with basic parameters
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (compressedFile != null) {
        final newFile = File(compressedFile.path);
        final compressedSize = await newFile.length();
        final compressionRatio = (1 - (compressedSize / fileSize)) * 100;
        
        print('Compressed file size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('Compression ratio: ${compressionRatio.toStringAsFixed(1)}%');
        
        return newFile;
      }

      return file;
    } catch (e) {
      print('Error compressing image: $e');
      return file;
    }
  }

  // Compress multiple images
  static Future<List<File>> compressImages(List<File> files) async {
    final List<File> compressedFiles = [];
    
    for (final file in files) {
      final compressedFile = await compressImage(file);
      if (compressedFile != null) {
        compressedFiles.add(compressedFile);
      }
    }
    
    return compressedFiles;
  }

  // Smart compression based on use case (matches TypeScript smartCompress)
  static Future<File?> smartCompress(
    File file, {
    String useCase = 'gallery', // 'gallery', 'color', or 'thumbnail'
  }) async {
    int quality;
    int maxWidth;
    int maxHeight;

    switch (useCase) {
      case 'gallery':
        quality = 90;
        maxWidth = 1920;
        maxHeight = 1920;
        break;
      case 'color':
        quality = 85;
        maxWidth = 800;
        maxHeight = 800;
        break;
      case 'thumbnail':
        quality = 80;
        maxWidth = 400;
        maxHeight = 400;
        break;
      default:
        quality = 90;
        maxWidth = 1920;
        maxHeight = 1920;
    }

    return compressImage(
      file,
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  // Different compression levels for different use cases (matches TypeScript)
  static Future<File?> compressForGallery(File file) async {
    return compressImage(
      file,
      quality: 90,
      maxWidth: 1920,
      maxHeight: 1920,
    );
  }

  static Future<File?> compressForColorImages(File file) async {
    return compressImage(
      file,
      quality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );
  }

  static Future<File?> compressForThumbnail(File file) async {
    return compressImage(
      file,
      quality: 80,
      maxWidth: 400,
      maxHeight: 400,
    );
  }

  // Check if file needs compression (matches TypeScript shouldCompress)
  static bool shouldCompress(File file, {int maxSizeKB = 500}) {
    final fileSize = file.lengthSync();
    final fileSizeKB = fileSize / 1024;
    return fileSizeKB > maxSizeKB;
  }

  // Get human-readable file size (matches TypeScript formatFileSize)
  static String formatFileSize(int bytes) {
    if (bytes == 0) return '0 Bytes';
    
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    final i = (bytes == 0) ? 0 : (bytes.bitLength - 1) ~/ 10;
    
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(2)} ${sizes[i]}';
  }

  // Simple compression method (recommended) - now matches TS quality
  static Future<File?> simpleCompress(File file) async {
    try {
      final fileSize = await file.length();
      
      // Skip if already small
      if (fileSize < 500 * 1024) return file;

      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_compressed.jpg',
      );

      // Use consistent 90% quality to match TypeScript
      const quality = 90;

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: 400,
        minHeight: 400,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (compressedFile != null) {
        return File(compressedFile.path);
      }
      
      return file;
    } catch (e) {
      print('Simple compression error: $e');
      return file;
    }
  }

  // E-commerce optimized compression - updated to match TS quality levels
  static Future<File?> ecommerceCompress(File file) async {
    try {
      final fileSize = await file.length();
      
      // Reject files larger than 20MB
      if (fileSize > 20 * 1024 * 1024) {
        throw Exception('File too large (max 20MB)');
      }
      
      // Skip if already small and good quality
      if (fileSize < 300 * 1024) return file;

      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_ecommerce_compressed.jpg',
      );

      // Use consistent quality levels matching TypeScript
      const quality = 90; // High quality for e-commerce
      const minWidth = 800;
      const minHeight = 800;

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (compressedFile != null) {
        final newFile = File(compressedFile.path);
        final compressedSize = await newFile.length();
        
        print('📊 E-commerce compression results:');
        print('   Original: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('   Compressed: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
        print('   Savings: ${(((fileSize - compressedSize) / fileSize) * 100).toStringAsFixed(1)}%');
        
        return newFile;
      }
      
      return file;
    } catch (e) {
      print('E-commerce compression error: $e');
      return file;
    }
  }
}