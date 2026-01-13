// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import '../providers/market_provider.dart';
// import '../providers/badge_provider.dart';
// import 'icon_with_badge.dart';
// import '../utils/route_transitions.dart';
// import '../generated/l10n/app_localizations.dart';
// import '../screens/favorite_product_screen.dart';
// import '../screens/my_cart_screen.dart';
// import '../screens/notification_screen.dart';
// import '../screens/inbox_screen.dart';
// import '../screens/login_screen.dart';
// import '../screens/list_product_screen.dart';
// import '../../providers/cart_provider.dart'; // Import new provider
// import '../../providers/favorite_product_provider.dart';

// class BottomNavBar extends StatelessWidget {
//   const BottomNavBar({Key? key}) : super(key: key);

//   Future<bool> _checkUserVerified(MarketProvider marketProvider) async {
//     final String? userId = marketProvider.currentUserId;
//     if (userId == null) return false;

//     final doc =
//         await FirebaseFirestore.instance.collection('users').doc(userId).get();
//     if (doc.exists) {
//       final data = doc.data() as Map<String, dynamic>;
//       return data['verified'] as bool? ?? false;
//     }
//     return false;
//   }

//   @override
//   Widget build(BuildContext context) {
//     final l10n = AppLocalizations.of(context)!;
//     const Color jadeGreen = Color(0xFF00A86B);

//     // Use selectors to only rebuild when these counts change.
//     final favoriteCount = context.select<FavoriteProvider, int>(
//       (provider) => provider.favoriteCount,
//     );
//     final cartCount = context.select<CartProvider, int>(
//       (provider) => provider.cartCount,
//     );

//     // For badges, still listen to the BadgeProvider's valueNotifiers.
//     final badgeProvider = Provider.of<BadgeProvider>(context, listen: true);

//     // Obtain a non-listening instance for calling actions.
//     final marketProvider = Provider.of<MarketProvider>(context, listen: false);

//     // Dimensions.
//     const double navBarHeight = 45.0;
//     const double buttonSize = 48.0;
//     const double marginHorizontal = 8.0;
//     const double marginBottom = 16.0;

//     return FutureBuilder<bool>(
//       future: _checkUserVerified(marketProvider),
//       builder: (context, snapshot) {
//         // Until the verification status is loaded, assume false.
//         bool isUserVerified = snapshot.hasData ? snapshot.data! : false;

//         // Build the list of navigation icons.
//         final List<Widget> navIcons = [
//           // Favorite Icon.
//           IconButton(
//             icon: IconWithBadge(
//               iconData: Icons.favorite,
//               badgeCount: favoriteCount,
//               label: l10n.favorites,
//             ),
//             onPressed: () {
//               marketProvider.resetSearch();
//               marketProvider.setBottomNavIndex(0);
//               Navigator.of(context).push(
//                 createSlideRoute(const FavoriteProductScreen()),
//               );
//             },
//           ),
//           // Cart Icon.
//           IconButton(
//             icon: IconWithBadge(
//               iconData: Icons.shopping_cart,
//               badgeCount: cartCount,
//               label: l10n.cart,
//             ),
//             onPressed: () {
//               marketProvider.resetSearch();
//               marketProvider.setBottomNavIndex(1);
//               Navigator.of(context).push(
//                 createSlideRoute(const MyCartScreen()),
//               );
//             },
//           ),
//           // Notifications Icon.
//           ValueListenableBuilder<int>(
//             valueListenable: badgeProvider.unreadNotificationsCount,
//             builder: (context, value, child) {
//               return IconButton(
//                 icon: IconWithBadge(
//                   iconData: Icons.notifications,
//                   badgeCount: value,
//                   label: l10n.notifications,
//                 ),
//                 onPressed: () {
//                   marketProvider.resetSearch();
//                   marketProvider.setBottomNavIndex(3);
//                   Navigator.of(context).push(
//                     createSlideRoute(const NotificationScreen()),
//                   );
//                 },
//               );
//             },
//           ),
//           // Mail Icon.
//           ValueListenableBuilder<int>(
//             valueListenable: badgeProvider.unreadMessagesCount,
//             builder: (context, value, child) {
//               return IconButton(
//                 icon: IconWithBadge(
//                   iconData: Icons.mail,
//                   badgeCount: value,
//                   label: l10n.inbox,
//                 ),
//                 onPressed: () {
//                   marketProvider.resetSearch();
//                   marketProvider.setBottomNavIndex(4);
//                   Navigator.of(context).push(
//                     createSlideRoute(const InboxScreen()),
//                   );
//                 },
//               );
//             },
//           ),
//         ];

//         List<Widget> rowChildren;
//         MainAxisAlignment alignment;
//         if (isUserVerified) {
//           rowChildren = [
//             navIcons[0],
//             navIcons[1],
//             const SizedBox(width: buttonSize), // Placeholder for "+" button.
//             navIcons[2],
//             navIcons[3],
//           ];
//           alignment = MainAxisAlignment.spaceAround;
//         } else {
//           rowChildren = navIcons;
//           alignment = MainAxisAlignment.spaceEvenly;
//         }

//         return Stack(
//           alignment: Alignment.bottomCenter,
//           clipBehavior: Clip.none,
//           children: [
//             // Navbar Container.
//             Container(
//               margin: const EdgeInsets.only(
//                 left: marginHorizontal,
//                 right: marginHorizontal,
//                 bottom: marginBottom,
//               ),
//               height: navBarHeight,
//               decoration: BoxDecoration(
//                 color: Theme.of(context).brightness == Brightness.dark
//                     ? const Color.fromARGB(255, 50, 46, 73)
//                     : Colors.grey[900],
//                 borderRadius: BorderRadius.circular(30.0),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withAlpha((0.3 * 255).round()),
//                     blurRadius: 10,
//                     offset: const Offset(0, 5),
//                   ),
//                 ],
//               ),
//               child: Theme(
//                 data: Theme.of(context).copyWith(
//                   iconTheme: const IconThemeData(
//                     color: Colors.white,
//                     size: 24.0,
//                   ),
//                   colorScheme: Theme.of(context)
//                       .colorScheme
//                       .copyWith(onSurface: Colors.white),
//                 ),
//                 child: Row(
//                   mainAxisAlignment: alignment,
//                   children: rowChildren,
//                 ),
//               ),
//             ),

//             // Floating "+" Button (only for verified users).
//             if (isUserVerified)
//               Positioned(
//                 bottom:
//                     marginBottom + (navBarHeight / 2) - (buttonSize / 2) + 5,
//                 child: GestureDetector(
//                   onTap: () {
//                     marketProvider.resetSearch();
//                     if (FirebaseAuth.instance.currentUser == null) {
//                       Navigator.of(context).push(
//                         createSlideRoute(const LoginScreen()),
//                       );
//                     } else {
//                       marketProvider.setBottomNavIndex(2);
//                       Navigator.of(context).push(
//                         createSlideRoute(const ListProductScreen()),
//                       );
//                     }
//                   },
//                   child: Container(
//                     width: buttonSize,
//                     height: buttonSize,
//                     decoration: BoxDecoration(
//                       color: jadeGreen,
//                       shape: BoxShape.circle,
//                       boxShadow: [
//                         BoxShadow(
//                           color: jadeGreen.withAlpha((0.6 * 255).round()),
//                           blurRadius: 8,
//                         ),
//                       ],
//                     ),
//                     child: const Icon(
//                       Icons.add,
//                       color: Colors.white,
//                       size: 26,
//                     ),
//                   ),
//                 ),
//               ),
//           ],
//         );
//       },
//     );
//   }
// }
