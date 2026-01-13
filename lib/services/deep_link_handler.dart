import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/share_service.dart';
import '../services/favorites_sharing_service.dart';
import '../generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../providers/favorite_product_provider.dart';

class DeepLinkHandler {
  static AppLinks? _appLinks;
  static StreamSubscription<Uri>? _linkSubscription;
  static BuildContext? _context;
  static bool _isInitialized = false;

  // ✅ PRODUCTION FIX: Add import state tracking to prevent duplicates
  static final Map<String, bool> _importInProgress = {};
  static final Set<String> _importedShareIds = {};

  static final List<String> _pendingLinks = [];

  /// Initialize deep link handling
  static Future<void> initialize(BuildContext context) async {
    if (_isInitialized) {
      debugPrint('DeepLinkHandler already initialized');
      return;
    }

    _context = context;
    _appLinks = AppLinks();

    // Process any pending links first
    if (_pendingLinks.isNotEmpty) {
      final pendingLink = _pendingLinks.removeAt(0);
      debugPrint('Processing pending deep link: $pendingLink');
      await _handleIncomingLink(pendingLink);
    }

    // Handle app launch from cold state
    await _handleInitialLink();

    // Handle app launch from warm state
    _linkSubscription = _appLinks!.uriLinkStream.listen(
      (Uri uri) => _handleIncomingLink(uri.toString()),
      onError: (err) {
        debugPrint('Deep link error: $err');
      },
    );

    _isInitialized = true;
    debugPrint('DeepLinkHandler initialized successfully');
  }

  /// Clean up resources
  static void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _appLinks = null;
    _context = null;
    _isInitialized = false;
    _pendingLinks.clear();
    
    // ✅ Clear import tracking
    _importInProgress.clear();
    _importedShareIds.clear();
    
    debugPrint('DeepLinkHandler disposed');
  }

  /// Handle initial link when app is launched
  static Future<void> _handleInitialLink() async {
    try {
      final initialUri = await _appLinks!.getInitialLink();
      if (initialUri != null) {
        debugPrint('App launched with deep link: ${initialUri.toString()}');
        await _handleIncomingLink(initialUri.toString(), isAppLaunch: true);
      } else {
        debugPrint('App launched normally (no deep link)');
      }
    } catch (e) {
      debugPrint('Error handling initial link: $e');
    }
  }

  /// Handle incoming deep links
  static Future<void> _handleIncomingLink(String link, {bool isAppLaunch = false}) async {
    debugPrint('🔗 Processing deep link: $link (isAppLaunch: $isAppLaunch)');

    // If context is null, queue the link for later processing
    if (_context == null || !_isInitialized) {
      debugPrint('⚠️ Context not ready, queueing deep link: $link');
      if (!_pendingLinks.contains(link)) {
        _pendingLinks.add(link);
      }
      return;
    }

    try {
      // Check if it's a shared favorites link first
      final shareId = _parseSharedFavoritesId(link);
      if (shareId != null) {
        debugPrint('✅ Detected shared favorites link with ID: $shareId');
        
        // ✅ PRODUCTION FIX: Check if already imported or in progress
        if (_importedShareIds.contains(shareId)) {
          debugPrint('⚠️ Share ID $shareId already imported, skipping');
          _showErrorMessage('These favorites have already been imported');
          return;
        }
        
        if (_importInProgress[shareId] == true) {
          debugPrint('⚠️ Import already in progress for $shareId');
          return;
        }

        // Navigate to the route and let it handle the import
        final router = GoRouter.of(_context!);
        router.go('/shared-favorites/$shareId');
        return;
      }

      // Parse product ID from deep link (existing functionality)
      final productId = ShareService.parseProductFromDeepLink(link);

      if (productId != null) {
        debugPrint('✅ Extracted product ID: $productId');
        await _navigateToProduct(productId, isAppLaunch: isAppLaunch);
      } else {
        debugPrint('❌ Could not parse any ID from link: $link');
        _showErrorMessage('Invalid link');
      }
    } catch (e) {
      debugPrint('❌ Error handling deep link: $e');
      _showErrorMessage('Failed to open link');
    }
  }

  /// Parse shared favorites ID from deep link
  static String? _parseSharedFavoritesId(String link) {
    try {
      debugPrint('Parsing shared favorites link: $link');

      // Handle app scheme URLs: nar24app://shared-favorites/abc123
      if (link.contains('://shared-favorites/')) {
        final uri = Uri.parse(link);
        debugPrint(
            'Parsed URI: scheme=${uri.scheme}, host=${uri.host}, path=${uri.path}');

        // For app schemes, the format is: nar24app://shared-favorites/abc123
        // The host will be 'shared-favorites' and path will be '/abc123'
        if (uri.host == 'shared-favorites' && uri.path.isNotEmpty) {
          final shareId =
              uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
          debugPrint('✅ Extracted share ID from app scheme: $shareId');
          return shareId;
        }
      }

      // Handle web URLs: https://yourapp.com/shared-favorites/abc123
      if (link.contains('/shared-favorites/')) {
        final uri = Uri.parse(link);
        final segments = uri.pathSegments;
        debugPrint('Path segments: $segments');

        // ✅ SAFE: Find 'shared-favorites' segment and get the next one
        for (int i = 0; i < segments.length; i++) {
          if (segments[i] == 'shared-favorites' && i + 1 < segments.length) {
            final shareId = segments[i + 1];
            debugPrint('✅ Extracted share ID from web URL: $shareId');
            return shareId;
          }
        }
      }

      // Handle query parameters as fallback
      final uri = Uri.parse(link);
      final shareId = uri.queryParameters['shareId'];
      if (shareId != null && shareId.isNotEmpty) {
        debugPrint('✅ Extracted share ID from query params: $shareId');
        return shareId;
      }

      debugPrint('❌ Could not extract share ID from link');
      return null;
    } catch (e) {
      debugPrint('❌ Error parsing shared favorites ID: $e');
      return null;
    }
  }

  /// Handle shared favorites import
  static Future<void> handleSharedFavorites(
    String shareId, BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final currentUser = FirebaseAuth.instance.currentUser;

  if (currentUser == null) {
    _showErrorMessage('Please log in to import favorites');
    return;
  }

  // ✅ PRODUCTION FIX: Prevent duplicate imports with comprehensive checks
  if (_importedShareIds.contains(shareId)) {
    debugPrint('Share ID $shareId already imported');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('These favorites have already been imported')),
    );
    return;
  }

  if (_importInProgress[shareId] == true) {
    debugPrint('Import already in progress for $shareId');
    return;
  }

  // Check if this shareId was already imported by checking existing baskets
  try {
    final existingBaskets = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('favorite_baskets')
        .where('importedFrom', isEqualTo: shareId)
        .get();

    if (existingBaskets.docs.isNotEmpty) {
      debugPrint('Share ID $shareId already exists in user baskets');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('These favorites have already been imported')),
      );
      _importedShareIds.add(shareId);
      return;
    }
  } catch (e) {
    debugPrint('Error checking existing imports: $e');
  }

  // Mark import as in progress
  _importInProgress[shareId] = true;

  try {
    // Show loading modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 16),
              Text(l10n.importingFavorites),
            ],
          ),
        ),
      ),
    );

    final sharedData =
        await FavoritesSharingService.getSharedFavorites(shareId);

    if (sharedData == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorImportingFavorites)),
      );
      return;
    }

    // Check basket limit
    final basketsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('favorite_baskets')
        .get();

    if (basketsSnapshot.docs.length >= 10) {
      Navigator.pop(context);

      final senderName =
          sharedData['senderName'] as String? ?? 'Unknown User';
      final brightness = Theme.of(context).brightness;
      final actionTextStyle = TextStyle(
          color:
              brightness == Brightness.light ? Colors.black : Colors.white);

      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(
            l10n.cannotAddFavorites(senderName),
            style: actionTextStyle,
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.confirm, style: actionTextStyle),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ Extract data with proper null checking and defaults
    final senderName = sharedData['senderName'] as String? ?? 'Unknown User';
    final basketName = sharedData['basketName'] as String? ?? 'Shared Basket';
    final fullBasketName = '$senderName\'s $basketName';
    final senderUid = sharedData['senderUid'] as String? ?? '';

    // ✅ PRODUCTION FIX: Use shareId as importedFrom for better tracking
    final basketRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('favorite_baskets')
        .add({
      'name': fullBasketName,
      'createdAt': FieldValue.serverTimestamp(),
      'importedFrom': shareId,
      'originalSender': senderUid,
    });

    // ✅ PRODUCTION FIX: Track imported product IDs for global favorites update
    final importedProductIds = <String>{};
    
    // ✅ PRODUCTION FIX: Use a single batch operation to prevent race conditions
    final batch = FirebaseFirestore.instance.batch();
    int successCount = 0;

    final favoritesData = sharedData['favorites'];
    if (favoritesData is List && favoritesData.isNotEmpty) {
      for (var favoriteItem in favoritesData) {
        try {
          if (favoriteItem is Map) {
            final favoriteMap = Map<String, dynamic>.from(favoriteItem);
            final favRef = basketRef.collection('favorites').doc();
            
            // ✅ Extract productId for global favorites tracking
            final productId = favoriteMap['productId'] as String?;
            if (productId != null && productId.isNotEmpty) {
              importedProductIds.add(productId);
            }

            batch.set(favRef, {
              ...favoriteMap,
              'addedAt': FieldValue.serverTimestamp(),
              'importedAt': FieldValue.serverTimestamp(),
              'sourceShareId': shareId,
            });
            successCount++;
          }
        } catch (e) {
          debugPrint('Error processing favorite item: $e');
        }
      }
    }

    // ✅ PRODUCTION FIX: Execute batch atomically
    if (successCount > 0) {
      await batch.commit();
      debugPrint('Successfully imported $successCount favorites');
      
      // ✅ CRITICAL FIX: Update global favorites notifier so UI reflects the import
      if (importedProductIds.isNotEmpty && context.mounted) {
        try {
          final favoriteProvider = Provider.of<FavoriteProvider>(context, listen: false);
          favoriteProvider.addToGlobalFavorites(importedProductIds);
          debugPrint('✅ Updated global favorites with ${importedProductIds.length} imported products');
        } catch (e) {
          debugPrint('⚠️ Could not update FavoriteProvider: $e');
          // Fallback: trigger a full refresh of global favorites
          try {
            final favoriteProvider = Provider.of<FavoriteProvider>(context, listen: false);
            await favoriteProvider.refreshGlobalFavorites();
          } catch (e2) {
            debugPrint('⚠️ Fallback refresh also failed: $e2');
          }
        }
      }
    }

    // ✅ Mark as successfully imported
    _importedShareIds.add(shareId);

    Navigator.pop(context); // Close loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(l10n.favoritesImported),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  } catch (e) {
    // ✅ Always ensure loading dialog is closed
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.errorImportingFavorites}: $e')),
    );
    debugPrint('Error importing favorites: $e');
  } finally {
    // ✅ PRODUCTION FIX: Always clear the in-progress flag
    _importInProgress.remove(shareId);
  }
}

  /// ✅ FIXED: Navigate to product detail screen with proper navigation handling
  static Future<void> _navigateToProduct(String productId, {bool isAppLaunch = false}) async {
    if (_context == null || !_context!.mounted) {
      debugPrint('Context is null or not mounted, cannot navigate');
      return;
    }

    try {
      final router = GoRouter.of(_context!);
      
      // ✅ CRITICAL FIX: Different navigation strategies based on context
      if (isAppLaunch) {
        // App was launched from cold state - replace the entire navigation stack
        debugPrint('🔥 App launched from deep link - replacing navigation stack');
        router.go('/product/$productId', extra: {'fromShare': true});
      } else {
        // App was already running - check current route and navigate appropriately
        debugPrint('🔄 App already running - checking current route');
        
        final currentLocation = router.routerDelegate.currentConfiguration.uri.toString();
        debugPrint('📍 Current location: $currentLocation');
        
        if (currentLocation == '/') {
          // Currently on home screen - push to product
          debugPrint('🏠 On home screen - pushing to product');
          router.push('/product/$productId', extra: {'fromShare': false});
        } else if (currentLocation.contains('/product/')) {
          // Already on a product screen - replace with new product
          debugPrint('📱 Already on product screen - replacing');
          router.pushReplacement('/product/$productId', extra: {'fromShare': false});
        } else {
          // On some other screen - navigate to product with proper back handling
          debugPrint('🔀 On other screen - navigating to product');
          router.push('/product/$productId', extra: {'fromShare': false});
        }
      }
    } catch (e) {
      debugPrint('Error navigating to product: $e');
      // Fallback: try to go to home and then to product
      try {
        final router = GoRouter.of(_context!);
        router.go('/');
        // Wait a frame then navigate to product
        await Future.delayed(const Duration(milliseconds: 100));
        router.push('/product/$productId', extra: {'fromShare': false});
      } catch (fallbackError) {
        debugPrint('Fallback navigation also failed: $fallbackError');
        _showErrorMessage('Could not open product');
      }
    }
  }

  /// Show error message
  static void _showErrorMessage(String message) {
    if (_context == null || !_context!.mounted) {
      debugPrint('Cannot show error message: context is null or not mounted');
      return;
    }

    try {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(message),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint('Error showing error message: $e');
    }
  }

  /// Manually handle a deep link (useful for testing)
  static Future<void> handleLink(String link) async {
    await _handleIncomingLink(link);
  }

  /// Add method to update context (useful for hot reloads)
  static void updateContext(BuildContext context) {
    _context = context;
  }

  /// Add method to check if there are pending links
  static bool hasPendingLinks() {
    return _pendingLinks.isNotEmpty;
  }

  /// Add method to manually process pending links
  static Future<void> processPendingLinks() async {
    if (_context != null && _pendingLinks.isNotEmpty) {
      final link = _pendingLinks.removeAt(0);
      await _handleIncomingLink(link);
    }
  }

  /// ✅ PRODUCTION FIX: Add method to reset import tracking (useful for testing)
  static void resetImportTracking() {
    _importInProgress.clear();
    _importedShareIds.clear();
    debugPrint('Import tracking reset');
  }

  /// ✅ PRODUCTION FIX: Add method to check if share was already imported
  static bool wasAlreadyImported(String shareId) {
    return _importedShareIds.contains(shareId);
  }
}