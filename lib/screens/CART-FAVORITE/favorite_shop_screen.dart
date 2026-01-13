// lib/screens/favorite_shop_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../SHOP-SCREENS/shop_screen.dart'; // For navigating to ShopScreen when no favorites
import '../../widgets/shop/shop_card_widget.dart';

class FavoriteShopScreen extends StatefulWidget {
  const FavoriteShopScreen({Key? key}) : super(key: key);

  @override
  _FavoriteShopScreenState createState() => _FavoriteShopScreenState();
}

class _FavoriteShopScreenState extends State<FavoriteShopScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<QueryDocumentSnapshot> _favoriteShops = [];
  Set<String> _favoriteShopIds = {};

  User? _currentUser;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _fetchFavoriteShops();
  }

  Future<void> _fetchFavoriteShops() async {
    setState(() {
      _isLoading = true;
    });
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        // Fetch favorite shop IDs from the user's subcollection
        QuerySnapshot favoriteSnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('favoriteShops')
            .get();

        setState(() {
          _favoriteShopIds = favoriteSnapshot.docs.map((doc) => doc.id).toSet();
        });

        // Fetch shop data for favorite shops (Firestore limits 'whereIn' to 10 items per query)
        if (_favoriteShopIds.isNotEmpty) {
          List<String> shopIds = _favoriteShopIds.toList();
          List<List<String>> batches = [];

          for (var i = 0; i < shopIds.length; i += 10) {
            batches.add(
              shopIds.sublist(
                i,
                i + 10 > shopIds.length ? shopIds.length : i + 10,
              ),
            );
          }

          List<QueryDocumentSnapshot> allShops = [];

          for (var batch in batches) {
            QuerySnapshot shopSnapshot = await _firestore
                .collection('shops')
                .where(FieldPath.documentId, whereIn: batch)
                .get();
            allShops.addAll(shopSnapshot.docs);
          }

          setState(() {
            _favoriteShops = allShops;
          });
        } else {
          setState(() {
            _favoriteShops = [];
          });
        }
      } catch (e) {
        print('Error fetching favorite shops: $e');
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  /// Creates a custom page transition route.
  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); // Slide in from right
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        final tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          l10n.favoriteShops,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 1,
        actions: const [],
      ),
      body: _isLoading
          ? Center(
              child: SpinKitFadingCircle(
                color: Theme.of(context).colorScheme.primary,
                size: 50.0,
              ),
            )
          : _favoriteShops.isEmpty
              ? _buildEmptyState(context)
              : RefreshIndicator(
                  onRefresh: _fetchFavoriteShops,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      // Wrap the grid in padding
                      SliverPadding(
                        padding: const EdgeInsets.all(8.0),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8.0,
                            mainAxisSpacing: 8.0,
                            childAspectRatio: 0.73,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              var shopData = _favoriteShops[index].data()
                                  as Map<String, dynamic>;
                              var shopId = _favoriteShops[index].id;
                              return ShopCardWidget(
                                shop: shopData,
                                shopId: shopId,
                                averageRating:
                                    0.0, // Default value; update if needed.
                              );
                            },
                            childCount: _favoriteShops.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display a placeholder GIF/image
            Image.asset(
              'assets/images/favorite.gif',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            // Descriptive text encouraging the user to discover shops.
            Text(
              l10n.discoverShops,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 20),
            // Button to navigate to the main shop screen.
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, _createRoute(const ShopScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: Text(
                l10n.addShops,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
