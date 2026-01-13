import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../theme.dart';
import '../../providers/market_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../widgets/product_list_sliver.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UserProfileProvider>(context, listen: false)
          .initialize(widget.userId);
    });

    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final provider = Provider.of<UserProfileProvider>(context, listen: false);
      if (!provider.isLoadingMore && provider.hasMoreProducts) {
        provider.loadMoreProducts();
      }
    }
  }

  Future<void> _handleFavoritePressed(UserProfileProvider provider) async {
    await provider.toggleFollowing(widget.userId);
  }

  void _showReportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black87
                : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.image,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  title: Text(
                    AppLocalizations.of(context).inappropriateProfileImage,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _submitReport('inappropriate_profile_image');
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.list,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  title: Text(
                    AppLocalizations.of(context).inappropriateListings,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _submitReport('inappropriate_listings');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submitReport(String reportType) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).pleaseLoginFirst,
              style: const TextStyle(fontFamily: 'Figtree'),
            ),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('reports')
          .add({
        'reporterId': currentUser.uid,
        'reportType': reportType,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).reportSubmittedSuccessfully,
            style: const TextStyle(fontFamily: 'Figtree'),
          ),
        ),
      );
    } catch (e) {
      print('Error submitting report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).errorSubmittingReport,
            style: const TextStyle(fontFamily: 'Figtree'),
          ),
        ),
      );
    }
  }

  Widget _buildSearchBox(String hint) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color.fromARGB(255, 33, 31, 49) : Colors.grey[200]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        onChanged: (value) {
          if (_debounce?.isActive ?? false) _debounce!.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            Provider.of<UserProfileProvider>(context, listen: false)
                .setSearchQuery(value);
          });
        },
        style: const TextStyle(fontSize: 14, fontFamily: 'Figtree'),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          filled: true,
          fillColor: backgroundColor,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50.0),
            borderSide: BorderSide(color: backgroundColor, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50.0),
            borderSide: BorderSide(color: backgroundColor, width: 1.0),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    final l10n = AppLocalizations.of(context);

    return Consumer2<UserProfileProvider, MarketProvider>(
      builder: (context, profileProvider, marketProvider, child) {
        if (profileProvider.isLoading) {
          return Scaffold(
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Colors.grey[100]
                : Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : Theme.of(context).appBarTheme.backgroundColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: profileProvider.userData != null &&
                            profileProvider.userData!['profileImage'] != null
                        ? CachedNetworkImageProvider(
                            profileProvider.userData!['profileImage'])
                        : const AssetImage('assets/images/default_avatar.png')
                            as ImageProvider,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profileProvider.userData != null
                          ? profileProvider.userData!['displayName'] ??
                              l10n.noUserName
                          : l10n.userProfile,
                      style: Theme.of(context)
                          .appBarTheme
                          .titleTextStyle
                          ?.copyWith(fontFamily: 'Figtree'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                if (!profileProvider.isCurrentUser) ...[
                  IconButton(
                    icon: Icon(
                      profileProvider.isFollowing
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: profileProvider.isFollowing
                          ? Colors.red
                          : Theme.of(context).brightness == Brightness.light
                              ? Colors.black
                              : Colors.white,
                    ),
                    onPressed: () => _handleFavoritePressed(profileProvider),
                  ),
                  IconButton(
                    icon: const Icon(Icons.report),
                    onPressed: _showReportOptions,
                  ),
                ],
              ],
            ),
            body: Center(
              child: CircularProgressIndicator(
                color: customColors?.badgeColor ??
                    Theme.of(context).colorScheme.secondary,
              ),
            ),
          );
        }

        if (profileProvider.userData == null) {
          return Scaffold(
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Colors.grey[100]
                : Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : Theme.of(context).appBarTheme.backgroundColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                l10n.userProfile,
                style: Theme.of(context)
                    .appBarTheme
                    .titleTextStyle
                    ?.copyWith(fontFamily: 'Figtree'),
              ),
              actions: [
                if (!profileProvider.isCurrentUser) ...[
                  IconButton(
                    icon: const Icon(Icons.report),
                    onPressed: _showReportOptions,
                  ),
                ],
              ],
            ),
            body: Center(
              child: Text(
                l10n.userNotFound,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFamily: 'Figtree',
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          );
        }

        final filteredProducts = profileProvider.products;

        return Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.light
              ? Colors.grey[100]
              : Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : Theme.of(context).appBarTheme.backgroundColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: profileProvider.userData != null &&
                          profileProvider.userData!['profileImage'] != null
                      ? CachedNetworkImageProvider(
                          profileProvider.userData!['profileImage'])
                      : const AssetImage('assets/images/default_avatar.png')
                          as ImageProvider,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profileProvider.userData!['displayName'] ?? l10n.noUserName,
                    style: Theme.of(context)
                        .appBarTheme
                        .titleTextStyle
                        ?.copyWith(fontFamily: 'Figtree'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (!profileProvider.isCurrentUser) ...[
                IconButton(
                  icon: Icon(
                    profileProvider.isFollowing
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: profileProvider.isFollowing
                        ? Colors.red
                        : Theme.of(context).brightness == Brightness.light
                            ? Colors.black
                            : Colors.white,
                  ),
                  onPressed: () => _handleFavoritePressed(profileProvider),
                ),
                IconButton(
                  icon: const Icon(Icons.report),
                  onPressed: _showReportOptions,
                ),
              ],
            ],
          ),
          body: SafeArea(
            top: true,
            bottom: false,
            child: GestureDetector(
              onTap: () => _focusNode.unfocus(),
              child: NestedScrollView(
                controller: _scrollController, // Add scroll controller here
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(
                      child: SellerInfoCard(
                        averageRating: profileProvider.averageRating,
                        reviewCount: profileProvider.reviewCount,
                        sellerTotalProductsSold:
                            profileProvider.sellerTotalProductsSold,
                        totalListings: filteredProducts.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(
                      child: _buildSearchBox(l10n.searchProducts),
                    ),
                  ];
                },
                body: filteredProducts.isEmpty
                    ? CustomScrollView(
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text(
                                AppLocalizations.of(context).noProductsFound,
                                style: const TextStyle(
                                    fontSize: 16, fontFamily: 'Figtree'),
                              ),
                            ),
                          ),
                        ],
                      )
                    : CustomScrollView(
                        slivers: [
                          ProductListSliver(
                            products: filteredProducts,
                            boostedProducts: [],
                            hasMore: profileProvider.hasMoreProducts,
                            isLoadingMore: profileProvider.isLoadingMore,
                            selectedColor: null,
                            screenName: 'user_profile_screen',
                          ),
                          // Loading indicator at bottom
                          if (profileProvider.isLoadingMore)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: customColors?.badgeColor ??
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                          // End message
                          if (!profileProvider.hasMoreProducts &&
                              filteredProducts.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// User Detail Card
class UserDetailCard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final bool isCurrentUser;
  final bool isFollowing;
  final VoidCallback onChatPressed;
  final VoidCallback onFavoritePressed;

  const UserDetailCard({
    Key? key,
    required this.userData,
    required this.isCurrentUser,
    required this.isFollowing,
    required this.onChatPressed,
    required this.onFavoritePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final cardColor = brightness == Brightness.light
        ? const Color.fromARGB(255, 245, 245, 245)
        : const Color.fromARGB(255, 39, 36, 57);

    final cardElevation = brightness == Brightness.light ? 0.0 : 2.0;
    final iconDefaultColor =
        brightness == Brightness.light ? Colors.black : Colors.white;

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      elevation: cardElevation,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 35,
              backgroundImage: userData['profileImage'] != null
                  ? CachedNetworkImageProvider(userData['profileImage'])
                  : const AssetImage('assets/images/default_avatar.png')
                      as ImageProvider,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: userData['displayName'] ?? l10n.noUserName,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                fontFamily: 'Figtree',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        if (userData['verified'] == true)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Image.asset(
                                'assets/images/verify2.png',
                                width: 24,
                                height: 24,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!isCurrentUser)
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.mail,
                            color: iconDefaultColor,
                          ),
                          onPressed: onChatPressed,
                        ),
                        IconButton(
                          icon: Icon(
                            isFollowing
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: isFollowing ? Colors.red : iconDefaultColor,
                          ),
                          onPressed: onFavoritePressed,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Gradient Text Widget
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign textAlign;

  const GradientText(
    this.text, {
    Key? key,
    this.style,
    required this.gradient,
    this.textAlign = TextAlign.left,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return gradient
            .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
      },
      child: Text(
        text,
        textAlign: textAlign,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}

// Seller Info Card
class SellerInfoCard extends StatelessWidget {
  final double averageRating;
  final int reviewCount;
  final int sellerTotalProductsSold;
  final int totalListings;

  const SellerInfoCard({
    Key? key,
    required this.averageRating,
    required this.reviewCount,
    required this.sellerTotalProductsSold,
    required this.totalListings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Numeric values style (keep same size)
    final numericTextStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontFamily: 'Figtree',
          fontWeight: FontWeight.bold,
          fontSize: 14, // Keep same size for numbers
        );

    // Label style (smaller font size)
    final labelTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: 'Figtree',
          fontSize: 12, // Smaller font size for labels
          color: isDarkMode ? Colors.white : null, // White labels in dark mode
        );

    return Container(
      width: double.infinity,
      color: isDarkMode
          ? Color.fromARGB(255, 33, 31, 49) // Dark mode background
          : Colors.white, // Light mode background
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  children: [
                    Text(
                      l10n.rating,
                      style: labelTextStyle, // Use smaller label style
                    ),
                    const SizedBox(height: 4),
                    GradientText(
                      averageRating.toStringAsFixed(1),
                      gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.pink]),
                      style: numericTextStyle, // Keep original size for numbers
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  children: [
                    Text(
                      l10n.productsSold2,
                      style: labelTextStyle, // Use smaller label style
                    ),
                    const SizedBox(height: 4),
                    GradientText(
                      sellerTotalProductsSold.toString(),
                      gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.pink]),
                      style: numericTextStyle, // Keep original size for numbers
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  children: [
                    Text(
                      l10n.totalListings,
                      style: labelTextStyle, // Use smaller label style
                    ),
                    const SizedBox(height: 4),
                    GradientText(
                      totalListings.toString(),
                      gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.pink]),
                      style: numericTextStyle, // Keep original size for numbers
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey[300],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Column(
                  children: [
                    Text(
                      l10n.userReviews,
                      style: labelTextStyle, // Use smaller label style
                    ),
                    const SizedBox(height: 4),
                    GradientText(
                      reviewCount.toString(),
                      gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.pink]),
                      style: numericTextStyle, // Keep original size for numbers
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
