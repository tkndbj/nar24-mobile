import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/profile_provider.dart'
    show ProfileProvider, ProfileErrorType;
import '../../providers/shop_widget_provider.dart';
import '../../theme_provider.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/agreement_modal.dart';
import '../../auth_service.dart';
import '../../user_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/login_modal.dart';
import '../../providers/badge_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../utils/image_compression_utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Tracks whether user has confirmed logout and we're showing shimmer
  bool _isLoggingOut = false;

  /// Safety timeout timer to prevent stuck shimmer
  Timer? _logoutSafetyTimer;

  /// Maximum time to show shimmer before resetting (safety net)
  static const Duration _maxLogoutDuration = Duration(seconds: 6);

  /// Prevents showing agreement modal multiple times
  bool _agreementModalShown = false;

  @override
  void initState() {
    super.initState();
    // Check and show agreement modal after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowAgreementModal();
    });
  }

  @override
  void dispose() {
    _logoutSafetyTimer?.cancel();
    super.dispose();
  }

  /// Check if social user (Google/Apple) needs to accept agreements
  Future<void> _checkAndShowAgreementModal() async {
    if (_agreementModalShown) return;

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) return;

      // Verify token is valid
      try {
        await firebaseUser.getIdToken();
      } catch (e) {
        if (kDebugMode) debugPrint('User token invalid, skipping agreement modal: $e');
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // Only check for social users (Google/Apple) who bypass registration form
      if (!userProvider.isSocialUser) return;

      // Check local storage first
      final hasAcceptedLocally = await AgreementModal.hasAcceptedAgreements(firebaseUser.uid);
      if (hasAcceptedLocally) return;

      // Wait for profile state to be ready (max 3 seconds)
      int waitAttempts = 0;
      const maxWaitAttempts = 30;
      while (!userProvider.isProfileStateReady && waitAttempts < maxWaitAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitAttempts++;
        if (!mounted) return;
      }

      // Re-check auth
      if (FirebaseAuth.instance.currentUser == null) return;

      // Check Firestore as secondary source
      final profileData = userProvider.profileData;
      final hasAcceptedInFirestore = profileData?['agreementsAccepted'] == true;
      if (hasAcceptedInFirestore) return;

      _agreementModalShown = true;

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser == null) {
        _agreementModalShown = false;
        return;
      }

      await AgreementModal.show(context);

      if (mounted) {
        await userProvider.refreshUser();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking agreement status: $e');
    }
  }

  /// Safely reset logout state (with mounted check)
  void _endLogoutShimmer() {
    _logoutSafetyTimer?.cancel();
    if (mounted) {
      setState(() => _isLoggingOut = false);
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final localization = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return showCupertinoDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          content: Text(
            localization.logoutConfirmation,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
              fontSize: 14,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                localization.no,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            CupertinoDialogAction(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _startLogoutWithShimmer();
              },
              child: Text(
                localization.yes,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Initiates logout with shimmer loading state
  /// App's auth state management handles navigation automatically
  void _startLogoutWithShimmer() {
    // Prevent double-triggering
    if (_isLoggingOut) return;

    setState(() => _isLoggingOut = true);

    // Safety timer: reset shimmer if logout takes too long
    // This prevents users from ever getting stuck on shimmer
    _logoutSafetyTimer = Timer(_maxLogoutDuration, () {
      debugPrint('⚠️ Logout shimmer safety timer triggered');
      _endLogoutShimmer();
    });

    // Perform logout - app's auth state management handles navigation
    AuthService().logout().catchError((error) {
      debugPrint('❌ Logout failed: $error');
      _endLogoutShimmer();
    });
  }

  void _handleUnauthenticatedTap(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => LoginPromptModal(authService: AuthService()),
    );
  }

  void _showUploadingModal(
    NavigatorState navigator,
    AppLocalizations l10n,
    bool isDark,
  ) {
    navigator.push(
      DialogRoute(
          context: navigator.context,
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
                                      colors: [
                                        Colors.blue.shade400,
                                        Colors.blue.shade600
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: const Icon(
                                    Icons.account_circle,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            );
                          },
                          onEnd: () {
                            // Animation will naturally restart due to setState in builder
                          },
                        ),
                        const SizedBox(height: 24),

                        // Title
                        Text(
                          l10n.uploadingImage ?? 'Uploading Image',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          l10n.pleaseWait ?? 'Please wait...',
                          style: TextStyle(
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
                            backgroundColor:
                                isDark ? Colors.grey[700] : Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
    );
  }

  Future<void> _uploadProfileImage(
    BuildContext context,
    ProfileProvider provider,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _handleUnauthenticatedTap(context);
      return;
    }

    // Capture context-dependent values BEFORE any async operations
    // This prevents "use_build_context_synchronously" issues
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      // 1) Let user pick an image from gallery
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Remove imageQuality since compression will handle optimization
      );
      if (pickedFile == null) return; // user cancelled

      // ✅ Show the animated modal IMMEDIATELY after image is picked
      _showUploadingModal(navigator, l10n, isDark);

      // 2) Check file extension
      final path = pickedFile.path.toLowerCase();
      if (!(path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png') ||
          path.endsWith('.webp') ||
          path.endsWith('.heic') ||
          path.endsWith('.heif'))) {
        navigator.pop(); // Close modal
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.invalidImageFormat)),
        );
        return;
      }

      // 3) Check file size (<= 10 MB)
      final file = File(pickedFile.path);
      final bytes = await file.length();
      const maxBytes = 10 * 1024 * 1024; // 10 MB
      if (bytes > maxBytes) {
        navigator.pop(); // Close modal
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.imageTooLarge)),
        );
        return;
      }

      // 4) Compress the image before uploading
      debugPrint(
          '🖼️ Original image size: ${(bytes / 1024 / 1024).toStringAsFixed(2)} MB');

      final compressedFile =
          await ImageCompressionUtils.ecommerceCompress(file);
      final fileToUpload = compressedFile ?? file;

      final compressedSize = await fileToUpload.length();
      debugPrint(
          '✅ Compressed image size: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // 5) Upload to temporary location for moderation
      final ext = path.split('.').last;
      final tempFileName = 'temp_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final tempRef = FirebaseStorage.instance
          .ref()
          .child('temp_moderation/profile/${user.uid}/$tempFileName');

      await tempRef.putFile(
        fileToUpload,
        SettableMetadata(contentType: 'image/$ext'),
      );
      final tempUrl = await tempRef.getDownloadURL();

      debugPrint('📤 Temporary image uploaded for moderation');

      // 6) Call Vision API for content moderation
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
          navigator.pop(); // Close modal

          String errorMessage =
              l10n.imageRejected ?? 'Image contains inappropriate content';
          if (rejectionReason == 'adult_content') {
            errorMessage = l10n.adultContentError ??
                'Image contains explicit adult content';
          } else if (rejectionReason == 'violent_content') {
            errorMessage =
                l10n.violentContentError ?? 'Image contains violent content';
          }

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );

          debugPrint('❌ Image rejected: $rejectionReason');
          return;
        }

        debugPrint('✅ Image approved by content moderation');
      } catch (e) {
        // If moderation fails, delete temp file and abort
        debugPrint('❌ Content moderation error: $e');
        await tempRef.delete();
        navigator.pop(); // Close modal

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(l10n.moderationError ??
                'Failed to verify image content. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 7) Delete old profile image if exists
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          final oldImageUrl = userData?['profileImage'] as String?;

          if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
            try {
              await FirebaseStorage.instance.refFromURL(oldImageUrl).delete();
              debugPrint('🗑️ Old profile image deleted');
            } catch (e) {
              debugPrint('⚠️ Could not delete old image: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error checking old image: $e');
      }

      // 8) Move approved image to permanent location
      final storageRef =
          FirebaseStorage.instance.ref().child('profileImages').child(user.uid);

      // Copy from temp to final location
      final finalBytes = await fileToUpload.readAsBytes();
      await storageRef.putData(
        finalBytes,
        SettableMetadata(contentType: 'image/$ext'),
      );
      final downloadUrl = await storageRef.getDownloadURL();

      // Delete temp file
      await tempRef.delete();

      debugPrint('🎉 Profile image uploaded successfully to permanent storage');

      // 9) Update Firestore user's document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profileImage': downloadUrl});

      // 10) Close the animated modal
      navigator.pop();

      // 11) Notify provider to refresh user data
      provider.refreshUser();

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l10n.profileImageUpdated),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Make sure to close the animated modal if still open
      if (navigator.canPop()) {
        navigator.pop();
      }

      String errorMessage;
      if (e.toString().contains('too large')) {
        errorMessage = l10n.imageTooLarge;
      } else if (e.toString().contains('adult content') ||
          e.toString().contains('violent content') ||
          e.toString().contains('inappropriate content')) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      } else {
        errorMessage = l10n.profileImageUploadError(e.toString());
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: (e.toString().contains('content') ||
                  e.toString().contains('too large'))
              ? Colors.red
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Consumer2<ProfileProvider, ShopWidgetProvider>(
          builder: (context, profileProvider, shopProvider, _) {
            // Show shimmer during logout process
            if (_isLoggingOut) {
              return _buildLogoutShimmer(isDarkMode);
            }

            if (profileProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (profileProvider.errorMessage != null &&
                profileProvider.errorType != ProfileErrorType.none) {
              return _buildErrorWidget(
                context,
                profileProvider,
                theme,
                localization,
              );
            }

            final user = profileProvider.currentUser;
            final userData = profileProvider.userData;
            final isAuthenticated = user != null;
            final userOwnsShop = shopProvider.userOwnsShop;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: isAuthenticated
                                ? () => _uploadProfileImage(
                                    context, profileProvider)
                                : () => _handleUnauthenticatedTap(context),
                            child: ClipOval(
                              child: isAuthenticated &&
                                      userData?['profileImage'] != null
                                  ? CachedNetworkImage(
                                      imageUrl: userData!['profileImage'],
                                      placeholder: (context, url) =>
                                          const SizedBox.shrink(),
                                      fadeInDuration: Duration.zero,
                                      fadeOutDuration: Duration.zero,
                                      errorWidget: (context, url, error) =>
                                          const Icon(Icons.error),
                                      fit: BoxFit.cover,
                                      width: 60,
                                      height: 60,
                                    )
                                  : const Image(
                                      image: AssetImage(
                                          'assets/images/default_avatar.png'),
                                      width: 60,
                                      height: 60,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final currentUid =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUid != null) {
                                    context.push('/user_profile/$currentUid');
                                  } else {
                                    // If somehow user is null, fall back to login or do nothing
                                    context.push('/login');
                                  }
                                },
                                child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    user != null &&
                                            userData != null &&
                                            userData['displayName'] != null
                                        ? userData['displayName'] as String
                                        : user != null
                                            ? localization.noName
                                            : localization.notLoggedIn,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (isAuthenticated)
                                Text(
                                  userData?['email'] ?? localization.noEmail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textTheme.bodyMedium?.color
                                        ?.withAlpha(180),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (isAuthenticated)
                        Row(
                          children: [
                            Consumer<BadgeProvider>(
                              builder: (context, badgeProv, _) {
                                return ValueListenableBuilder<int>(
                                  valueListenable:
                                      badgeProv.unreadNotificationsCount,
                                  builder: (context, count, _) {
                                    final display =
                                        count > 10 ? '+10' : count.toString();
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        IconButton(
                                          icon: Icon(FeatherIcons.bell),
                                          color:
                                              theme.textTheme.bodyMedium?.color,
                                          iconSize: 20,
                                          onPressed: () =>
                                              context.push('/notifications'),
                                        ),
                                        if (count > 0)
                                          Positioned(
                                            right: 6,
                                            top: 6,
                                            child: Container(
                                              // make sure it's square
                                              constraints: const BoxConstraints(
                                                minWidth: 20,
                                                minHeight: 20,
                                              ),
                                              alignment: Alignment.center,
                                              decoration: const BoxDecoration(
                                                color: Color(
                                                    0xFF00A86B), // jade green
                                                shape: BoxShape
                                                    .circle, // ⚡️ circle shape
                                              ),
                                              child: Text(
                                                display,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        )
                      else
                        ElevatedButton(
                          onPressed: () {
                            context.push('/login');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange, // Changed to orange
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  0), // Changed to 0 for sharp corners
                            ),
                            elevation:
                                0, // Optional: remove elevation for a flatter look
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10), // Optional: adjust padding
                          ),
                          child: Text(
                            localization.loginButton,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  FontWeight.w600, // Optional: make text bolder
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Profile completion progress card (only shows if profile is incomplete)
                  if (isAuthenticated)
                    _buildProfileCompletionCard(
                      userData: userData,
                      theme: theme,
                      localization: localization,
                      isDarkMode: isDarkMode,
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTopButton(
                          icon: FeatherIcons.box,
                          label: localization.myProducts,
                          onTap: isAuthenticated
                              ? () => context.push('/myproducts')
                              : () => _handleUnauthenticatedTap(context),
                          theme: theme,
                        ),
                      ),
                      _verticalDivider(),
                      Expanded(
                        child: _buildTopButton(
                          icon: FeatherIcons.mapPin,
                          label: localization.myAdresses,
                          onTap: isAuthenticated
                              ? () => context.push('/addresses')
                              : () => _handleUnauthenticatedTap(context),
                          theme: theme,
                        ),
                      ),
                      _verticalDivider(),
                      Expanded(
                        child: _buildTopButton(
                          icon: FeatherIcons.info,
                          label: localization.sellerInfo,
                          onTap: isAuthenticated
                              ? () => context.push('/seller_info')
                              : () => _handleUnauthenticatedTap(context),
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: (userOwnsShop && shopProvider.firstUserShopId != null)
                            ? _buildSellerPanelButton(
                                label: localization.sellerPanel,
                                onTap: () => context.push(
                                    '/seller-panel?shopId=${shopProvider.firstUserShopId}'),
                                theme: theme,
                              )
                            : _buildRectButton(
                                icon: FeatherIcons.package,
                                label: localization.myOrders,
                                onTap: isAuthenticated
                                    ? () => context.push('/my_orders')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildRectButton(
                          icon: FeatherIcons.upload,
                          label: localization.sellOnVitrin,
                          onTap: isAuthenticated
                              ? () async {
                                  final userId =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (userId == null) {
                                    _handleUnauthenticatedTap(context);
                                    return;
                                  }
                                  // Capture router before async operation
                                  final router = GoRouter.of(context);
                                  final userDoc = await FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(userId)
                                      .get();
                                  final sellerInfo =
                                      userDoc.data()?['sellerInfo']
                                          as Map<String, dynamic>?;
                                  if (sellerInfo != null) {
                                    router.push('/list_product_screen');
                                  } else {
                                    router.push('/seller_info',
                                        extra: {'redirectToListProduct': true});
                                  }
                                }
                              : () => _handleUnauthenticatedTap(context),
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: userOwnsShop
                            ? _buildRectButton(
                                icon: FeatherIcons.package,
                                label: localization.myOrders,
                                onTap: isAuthenticated
                                    ? () => context.push('/my_orders')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              )
                            : _buildRectButton(
                                icon: FeatherIcons.star,
                                label: localization.myReviews,
                                onTap: isAuthenticated
                                    ? () => context.push('/my-reviews')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: userOwnsShop
                            ? _buildRectButton(
                                icon: FeatherIcons.star,
                                label: localization.myReviews,
                                onTap: isAuthenticated
                                    ? () => context.push('/my-reviews')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              )
                            : _buildRectButton(
                                icon: FeatherIcons.zap,
                                label: localization.boosts,
                                onTap: isAuthenticated
                                    ? () => context.push('/boost')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: userOwnsShop
                            ? _buildRectButton(
                                icon: FeatherIcons.zap,
                                label: localization.boosts,
                                onTap: isAuthenticated
                                    ? () => context.push('/boost')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              )
                            : _buildRectButton(
                                icon: FeatherIcons.helpCircle,
                                label: localization.myQuestions,
                                onTap: isAuthenticated
                                    ? () =>
                                        context.push('/user-product-questions')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: userOwnsShop
                            ? _buildRectButton(
                                icon: FeatherIcons.helpCircle,
                                label: localization.myQuestions,
                                onTap: isAuthenticated
                                    ? () =>
                                        context.push('/user-product-questions')
                                    : () => _handleUnauthenticatedTap(context),
                                theme: theme,
                              )
                            : Container(), // Empty container for non-shop owners
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height:
                        48, // any fixed height that makes sense for your design
                    child: Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              localization.darkMode,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                            value: themeProvider.isDarkMode,
                            onChanged: (value) =>
                                themeProvider.toggleThemeWithPersistence(value),
                            activeThumbColor: theme.colorScheme.secondary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        // ↓ Now this inner Row is guaranteed to be 48px tall
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                localization.settingsLanguage,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                              LanguageSelector(
                                iconColor:
                                    isDarkMode ? Colors.white : Colors.black,
                                iconSize: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isAuthenticated)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/receipts'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FeatherIcons.creditCard,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                localization.myReceipts,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/refund_form'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FeatherIcons.refreshCcw,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                localization.refundForm,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/create_shop_screen'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FeatherIcons.shoppingCart,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                localization.becomeASeller,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/account_settings'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FeatherIcons.settings,
                                  size: 18,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color),
                              const SizedBox(width: 8),
                              Text(
                                localization.accountSettings,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/support_and_faq'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FeatherIcons.info,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                localization.supportAndFaq,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          height: 1,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _showLogoutDialog(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FeatherIcons.power,
                                size: 18,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                localization.logout,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      color: Colors.grey[300],
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildTopButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: theme.textTheme.bodyMedium?.color,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRectButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildGradientIcon(icon, 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodyMedium?.color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              FeatherIcons.chevronRight,
              color: theme.textTheme.bodyMedium?.color,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerPanelButton({
    required String label,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            colors: [Colors.purple, Colors.pink],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                isDarkMode ? Color.fromARGB(255, 33, 31, 49) : theme.cardColor,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildGradientIcon(FeatherIcons.shoppingCart, 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                FeatherIcons.chevronRight,
                color: theme.textTheme.bodyMedium?.color,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientIcon(IconData icon, double size) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange, Colors.pink],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: Icon(
        icon,
        size: size,
        color: Colors.white,
      ),
    );
  }

  /// Builds shimmer placeholder during logout process
  /// Matches the profile screen layout for a smooth transition
  Widget _buildLogoutShimmer(bool isDarkMode) {
    final baseColor =
        isDarkMode ? const Color.fromARGB(255, 30, 28, 44) : Colors.grey[300]!;
    final highlightColor =
        isDarkMode ? const Color.fromARGB(255, 45, 42, 65) : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            // Profile header shimmer
            Row(
              children: [
                // Avatar
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // Name and email
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 180,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Top buttons row shimmer
            Row(
              children: [
                Expanded(child: _buildShimmerTopButton()),
                const SizedBox(width: 16),
                Expanded(child: _buildShimmerTopButton()),
                const SizedBox(width: 16),
                Expanded(child: _buildShimmerTopButton()),
              ],
            ),
            const SizedBox(height: 20),
            // Rect buttons shimmer (2 rows of 2)
            Row(
              children: [
                Expanded(child: _buildShimmerRectButton()),
                const SizedBox(width: 10),
                Expanded(child: _buildShimmerRectButton()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildShimmerRectButton()),
                const SizedBox(width: 10),
                Expanded(child: _buildShimmerRectButton()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildShimmerRectButton()),
                const SizedBox(width: 10),
                Expanded(child: _buildShimmerRectButton()),
              ],
            ),
            const SizedBox(height: 20),
            // Settings row shimmer
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 20),
            // Menu items shimmer
            ...List.generate(
                6,
                (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Container(
                        height: 20,
                        width: 160,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    )),
          ],
        ),
      ),
    );
  }

  /// Helper for shimmer top button placeholder
  Widget _buildShimmerTopButton() {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  /// Helper for shimmer rect button placeholder
  Widget _buildShimmerRectButton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  /// Builds a user-friendly error widget with retry button
  Widget _buildErrorWidget(
    BuildContext context,
    ProfileProvider profileProvider,
    ThemeData theme,
    AppLocalizations localization,
  ) {
    final isDarkMode = theme.brightness == Brightness.dark;
    final isNetworkError =
        profileProvider.errorType == ProfileErrorType.networkUnavailable;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.grey[800]?.withOpacity(0.5)
                    : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNetworkError
                    ? FeatherIcons.wifiOff
                    : FeatherIcons.alertCircle,
                size: 48,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            // Error title
            Text(
              localization.profileLoadingError,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Error description
            Text(
              isNetworkError
                  ? localization.profileNetworkError
                  : localization.profileUnknownError,
              style: TextStyle(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Retry button
            SizedBox(
              width: 160,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => profileProvider.retryFetch(),
                icon: const Icon(FeatherIcons.refreshCw, size: 18),
                label: Text(localization.retry),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calculates profile completion percentage based on required fields
  double _calculateProfileCompletion(Map<String, dynamic>? userData) {
    if (userData == null) return 0.0;

    int completedFields = 0;
    const int totalFields = 2; // gender, birthDate

    if (userData['gender'] != null) completedFields++;
    if (userData['birthDate'] != null) completedFields++;

    return completedFields / totalFields;
  }

  /// Builds the profile completion progress card
  /// Shows only when profile is incomplete
  Widget _buildProfileCompletionCard({
    required Map<String, dynamic>? userData,
    required ThemeData theme,
    required AppLocalizations localization,
    required bool isDarkMode,
  }) {
    final completionPercentage = _calculateProfileCompletion(userData);

    // Don't show if profile is complete
    if (completionPercentage >= 1.0) {
      return const SizedBox.shrink();
    }

    final completionPercent = (completionPercentage * 100).round();

    return GestureDetector(
      onTap: () => context.push('/complete-profile'),
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    const Color(0xFF2D2B3F),
                    const Color(0xFF1E1C2E),
                  ]
                : [
                    Colors.orange.shade50,
                    Colors.white,
                  ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? Colors.orange.withOpacity(0.3)
                : Colors.orange.shade200,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(isDarkMode ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: Colors.orange.shade600,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localization.completeYourProfile ??
                            'Complete Your Profile',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        localization.profileCompletionMessage ??
                            'Add your details to unlock all features',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  FeatherIcons.chevronRight,
                  color: Colors.orange.shade600,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: completionPercentage,
                      backgroundColor: isDarkMode
                          ? Colors.white.withOpacity(0.1)
                          : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.orange.shade500,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$completionPercent%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
