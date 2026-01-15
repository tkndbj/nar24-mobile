import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class FavoritesSharingService {
  static const String baseUrl = 'https://app.nar24.com/shared-favorites';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<String?> shareFavorites({
    required String? basketId,
    required String senderName,
    required BuildContext context,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // Get favorites from appropriate collection
      final collection = basketId == null
          ? _firestore.collection('users').doc(user.uid).collection('favorites')
          : _firestore
              .collection('users')
              .doc(user.uid)
              .collection('favorite_baskets')
              .doc(basketId)
              .collection('favorites');

      final snapshot = await collection.get();
      if (snapshot.docs.isEmpty) return null;

      // Get user's language code for localized content
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final languageCode = userDoc.data()?['languageCode'] ?? 'tr';

      // Get basket name with localization
      final basketName = basketId == null
          ? _getLocalizedText('general', languageCode)
          : (await _getBasketName(user.uid, basketId) ?? 'Unknown Basket');

      // Process favorites data
      final favorites = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        try {
          // Start with the basic favorite data structure
          final favoriteData = <String, dynamic>{};

          // Add productId with validation
          final productId = data['productId'] as String?;
          if (productId != null && productId.trim().isNotEmpty) {
            favoriteData['productId'] = productId.trim();
          } else {
            continue; // Skip this favorite if no productId
          }

          // Add other core fields with null safety
          if (data['addedAt'] != null) {
            favoriteData['addedAt'] = data['addedAt'];
          }

          final quantity = data['quantity'] as int?;
          favoriteData['quantity'] = quantity ?? 1;

          // Add all other top-level fields (except core ones we already handled)
          data.forEach((key, value) {
            if (value != null &&
                !['productId', 'addedAt', 'quantity', 'attributes']
                    .contains(key)) {
              // Extra validation for string fields
              if (value is String) {
                final trimmedValue = value.trim();
                if (trimmedValue.isNotEmpty) {
                  favoriteData[key] = trimmedValue;
                }
              } else {
                favoriteData[key] = value;
              }
            }
          });

          // Add all attributes with validation
          final attributes = data['attributes'] as Map<String, dynamic>? ?? {};

          attributes.forEach((key, value) {
            if (value != null) {
              // Extra validation for string fields
              if (value is String) {
                final trimmedValue = value.trim();
                if (trimmedValue.isNotEmpty) {
                  favoriteData[key] = trimmedValue;
                }
              } else {
                favoriteData[key] = value;
              }
            }
          });

          favorites.add(favoriteData);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Error processing favorite: $e');
          }
          // Continue with other favorites
        }
      }

      if (favorites.isEmpty) return null;

      // Validate all required fields before creating share data
      final safeSenderName =
          senderName.trim().isEmpty ? 'Anonymous' : senderName.trim();
      final safeBasketName =
          basketName.trim().isEmpty ? 'General' : basketName.trim();

      // Create share data
      final shareTitle =
          _getLocalizedShareTitle(safeSenderName, safeBasketName, languageCode);
      final shareDescription =
          _getLocalizedShareDescription(favorites.length, languageCode);

      final shareData = {
        'senderUid': user.uid,
        'senderName': safeSenderName,
        'basketName': safeBasketName,
        'languageCode': languageCode,
        'itemCount': favorites.length,
        'shareTitle': shareTitle,
        'shareDescription': shareDescription,
        'appName': 'Nar24',
        'appIcon': 'https://app.nar24.com/assets/images/naricon.png',
        'favorites': favorites,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      };

      // Store in shared_favorites collection
      final docRef =
          await _firestore.collection('shared_favorites').add(shareData);

      final shareUrl = '$baseUrl/${docRef.id}';
      return shareUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in shareFavorites: $e');
      }
      return null;
    }
  }

  static String _getLocalizedText(String key, String languageCode) {
    final localizations = {
      'general': {
        'tr': 'Genel',
        'en': 'General',
        'ru': 'Общие',
      },
      'share_favorites': {
        'tr': 'Favorileri Paylaş',
        'en': 'Share Favorites',
        'ru': 'Поделиться избранным',
      },
      'copy_link': {
        'tr': 'Bağlantı Kopyala',
        'en': 'Copy Link',
        'ru': 'Скопировать ссылку',
      },
      'email': {
        'tr': 'E-posta',
        'en': 'Email',
        'ru': 'Электронная почта',
      },
    };

    return localizations[key]?[languageCode] ??
        localizations[key]?['tr'] ??
        key;
  }

 static Future<ShareResult?> shareWithRichContent({
  required String shareTitle,
  required String shareUrl,
  required String senderName,
  required String basketName,
  required int itemCount,
  required String languageCode,
  Rect? sharePositionOrigin,
  BuildContext? context,
}) async {
  if (kDebugMode) {
    debugPrint('🚀 Using native share dialog...');
  }

  try {
    // ✅ Validate inputs
    final sanitizedTitle = shareTitle.trim();
    final sanitizedUrl = shareUrl.trim();

    if (sanitizedTitle.isEmpty || sanitizedUrl.isEmpty) {
      throw Exception('Share content cannot be empty');
    }

    // ✅ Create share text
    final shareText = '$sanitizedTitle\n\n$sanitizedUrl';

    // ✅ Small delay for Android stability
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // ✅ Use native share dialog
    final result = await Share.share(
      shareText,
      subject: sanitizedTitle,
      sharePositionOrigin: sharePositionOrigin,
    );

    if (kDebugMode) {
      debugPrint('✅ Share completed with status: ${result.status}');
    }

    return result;

  } on PlatformException catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Platform error: ${e.code} - ${e.message}');
    }
    if (context != null && context.mounted) {
      await _handleShareError(shareUrl, shareTitle, context);
    }
    return null;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('❌ Share error: $e\n$stackTrace');
    }
    if (context != null && context.mounted) {
      await _handleShareError(shareUrl, shareTitle, context);
    }
    return null;
  }
}


  static Future<void> _handleShareError(
      String shareUrl, String shareTitle, BuildContext? context) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Using clipboard fallback...');
      }

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: shareUrl));

      if (kDebugMode) {
        debugPrint('✅ URL copied to clipboard');
      }

      // Show user-friendly message
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.content_copy, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Share unavailable - link copied to clipboard',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } catch (clipboardError) {
      if (kDebugMode) {
        debugPrint('❌ Clipboard fallback also failed: $clipboardError');
      }
    }
  }

  static String createSimpleShareContent({
    required String shareTitle,
    required String shareUrl,
  }) {
    final title =
        shareTitle.trim().isEmpty ? 'Shared Favorites' : shareTitle.trim();
    final url =
        shareUrl.trim().isEmpty ? 'https://app.nar24.com' : shareUrl.trim();
    return url;
  }

  static String createRichShareContent({
    required String shareTitle,
    required String shareUrl,
    required String senderName,
    required String basketName,
    required int itemCount,
    required String languageCode,
  }) {
    return shareUrl.trim().isEmpty ? 'https://app.nar24.com' : shareUrl.trim();
  }

  // Helper function to create localized share title
  static String _getLocalizedShareTitle(
      String senderName, String basketName, String languageCode) {
    final templates = {
      'tr': '$senderName\'in $basketName Favorileri',
      'en': '$senderName\'s $basketName Favorites',
      'ru': 'Избранное $basketName от $senderName',
    };

    return templates[languageCode] ?? templates['tr']!;
  }

  // Helper function to create localized share description
  static String _getLocalizedShareDescription(
      int itemCount, String languageCode) {
    final templates = {
      'tr': '$itemCount ürün içeriyor',
      'en': 'Contains $itemCount products',
      'ru': 'Содержит $itemCount товаров',
    };

    return templates[languageCode] ?? templates['tr']!;
  }

  static Future<String?> _getBasketName(String uid, String basketId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('favorite_baskets')
          .doc(basketId)
          .get();

      return doc.data()?['name'] as String?;
    } catch (e) {
      debugPrint('❌ Error getting basket name: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSharedFavorites(
      String shareId) async {
    try {
      final doc =
          await _firestore.collection('shared_favorites').doc(shareId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final expiresAt = data['expiresAt'] as Timestamp?;

      // Check if expired
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        return null;
      }

      return data;
    } catch (e) {
      debugPrint('Error getting shared favorites: $e');
      return null;
    }
  }
}

// ✅ Share option data class
class ShareOption {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback action;

  ShareOption({
    required this.name,
    required this.icon,
    required this.color,
    required this.action,
  });
}