// lib/services/share_service.dart

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';

class ShareService {
  // ✅ FIXED: Use your REAL website domain
  static const String baseUrl = 'https://www.nar24.com/productdetail';
  static const String appScheme = 'nar24app';

  /// ✅ SIMPLIFIED: Minimal product sharing like favorites
  static Future<void> shareProduct({
    required Product product,
    required BuildContext context,
    GlobalKey? widgetKey,
  }) async {
    try {
      // Create simple share URL
      final shareUrl = generateWebUrl(product);
      
      debugPrint('🔗 Sharing product URL: $shareUrl');
      
      // ✅ MINIMAL CONTENT: Just the URL (like favorites sharing)
      await Share.share(
        shareUrl,
        subject: '${product.brandModel ?? ''} ${product.productName}'.trim(),
      );

      debugPrint('✅ Successfully shared product: $shareUrl');
    } catch (e) {
      debugPrint('❌ Error sharing product: $e');
      // Fallback to simple text share
      await _fallbackShare(product, context);
    }
  }

  /// Generates a deep link for the product (PUBLIC METHOD)
  /// Prioritizes app launch over web
  static String generateDeepLink(Product product) {
    final collection =
        (product.shopId?.isNotEmpty == true) ? 'shop_products' : 'products';

    // ✅ Create app scheme URL first (this will launch the app directly)
    return '$appScheme://product/${product.id}?collection=$collection';
  }

  /// ✅ FIXED: Use your REAL website URL format
  static String generateWebUrl(Product product) {
    // ✅ CRITICAL FIX: Use your actual website URL format
    // This matches: https://www.nar24.com/productdetail/ed4ac5d2-20f9-47eb-ab6f-cbaed7341880
    final url = 'https://www.nar24.com/productdetail/${product.id}';
    debugPrint('🔗 Generated share URL: $url');
    return url;
  }

  /// Creates a shortened, branded URL that doesn't expose project details
  static Future<String> generateBrandedUrl(Product product) async {
    try {
      // Use your custom domain
      final webUrl = generateWebUrl(product);
      return webUrl;
    } catch (e) {
      debugPrint('Error generating branded URL: $e');
      // Fallback to app scheme
      return generateDeepLink(product);
    }
  }

  /// Fallback share method
  static Future<void> _fallbackShare(
      Product product, BuildContext context) async {
    final deepLink = generateDeepLink(product);
    await Share.share(deepLink);
  }

  /// Handles incoming deep links (supports both app scheme and web URLs)
  static String? parseProductFromDeepLink(String link) {
    try {
      final uri = Uri.parse(link);

      // Handle app scheme URLs (priority)
      if (uri.scheme == appScheme) {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && segments[0] == 'product') {
          return segments[1]; // product ID
        }
      }

      // ✅ FIXED: Handle your REAL website domain
      if (uri.host == 'www.nar24.com' || uri.host == 'nar24.com') {
        final segments = uri.pathSegments;
        // Handle /productdetail/{id} format
        if (segments.length >= 2 && segments[0] == 'productdetail') {
          return segments[1]; // product ID
        }
      }

      // ✅ BACKUP: Also handle app.nar24.com for backwards compatibility
      if (uri.host == 'app.nar24.com') {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && (segments[0] == 'products' || segments[0] == 'product')) {
          return segments[1]; // product ID
        }
      }

      // ✅ BACKUP: Also handle Firebase default domain as fallback
      if (uri.host == 'emlak-mobile-app.web.app') {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && (segments[0] == 'products' || segments[0] == 'product')) {
          return segments[1]; // product ID
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error parsing deep link: $e');
      return null;
    }
  }
}